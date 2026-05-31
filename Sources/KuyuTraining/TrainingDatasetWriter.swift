import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios

public struct TrainingDatasetWriter {
    public enum WriteError: Error {
        case closeFailedAfterWriteError(writeError: any Error, closeError: any Error)
    }

    public init() {}

    @discardableResult
    public func write(
        dataset: TrainingDataset,
        to directory: URL
    ) throws -> URL {
        try write(
            metadata: dataset.metadata,
            records: dataset.records,
            to: directory
        )
    }

    public func write(
        log: SimulationLog,
        to directory: URL,
        observation: TrainingObservationMetadata? = nil,
        provenance: TrainingProvenanceManifest? = nil,
        policyId: String? = nil,
        terminalFacts: ScenarioTerminalFacts? = nil,
        rewardDescriptor: RewardDescriptor? = nil,
        taskReference: TrainingTaskReferenceMetadata? = nil
    ) throws -> URL {
        let resolvedTerminalFacts = terminalFacts ?? ScenarioTerminalFacts(log: log)
        let records = buildRecords(from: log, terminalFacts: resolvedTerminalFacts)
        let metadata = TrainingDatasetMetadata(
            scenarioId: log.scenarioId.rawValue,
            seed: log.seed.rawValue,
            timeStep: log.timeStep.delta,
            determinismTier: log.determinism.tier.rawValue,
            configHash: log.configHash,
            channelCount: maxChannelCount(records),
            driveCount: maxDriveCount(records),
            recordCount: records.count,
            failureReason: resolvedTerminalFacts.failureReason?.rawValue,
            failureTime: resolvedTerminalFacts.failureTime,
            policyId: policyId,
            done: resolvedTerminalFacts.done,
            truncated: resolvedTerminalFacts.truncated,
            terminalReason: resolvedTerminalFacts.terminalReason,
            rewardDescriptor: rewardDescriptor,
            taskReference: taskReference,
            observation: observation,
            provenance: provenance
        )

        return try write(metadata: metadata, records: records, to: directory)
    }

    public func write(
        episode: RolloutEpisode,
        timeStep: Double,
        determinismTier: String,
        to directory: URL,
        observation: TrainingObservationMetadata? = nil,
        provenance: TrainingProvenanceManifest? = nil
    ) throws -> URL {
        try write(
            dataset: makeDataset(
                episode: episode,
                timeStep: timeStep,
                determinismTier: determinismTier,
                observation: observation,
                provenance: provenance
            ),
            to: directory
        )
    }

    public func makeDataset(
        episode: RolloutEpisode,
        timeStep: Double,
        determinismTier: String,
        observation: TrainingObservationMetadata? = nil,
        provenance: TrainingProvenanceManifest? = nil
    ) -> TrainingDataset {
        let records = buildRecords(from: episode)
        let metadata = TrainingDatasetMetadata(
            scenarioId: episode.scenarioId,
            seed: episode.seed,
            timeStep: timeStep,
            determinismTier: determinismTier,
            configHash: episode.configHash,
            channelCount: maxChannelCount(records),
            driveCount: maxDriveCount(records),
            recordCount: records.count,
            failureReason: episode.failureReason,
            failureTime: episode.failureTime,
            episodeId: episode.episodeId,
            policyId: episode.policyId,
            rewardSum: episode.rewardSum,
            done: episode.done,
            truncated: episode.truncated,
            terminalReason: episode.terminalReason,
            rewardDescriptor: episode.rewardDescriptor,
            taskReference: episode.taskReference,
            observation: observation,
            provenance: provenance
        )

        return TrainingDataset(metadata: metadata, records: records)
    }

    private func write(
        metadata: TrainingDatasetMetadata,
        records: [TrainingDatasetRecord],
        to directory: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]

        let metaURL = directory.appendingPathComponent("meta.json")
        let metaData = try encoder.encode(metadata)
        try metaData.write(to: metaURL, options: [.atomic])

        let recordsURL = directory.appendingPathComponent("records.jsonl")
        try Data().write(to: recordsURL, options: [.atomic])
        let handle = try FileHandle(forWritingTo: recordsURL)

        do {
            for record in records {
                let data = try encoder.encode(record)
                handle.write(data)
                handle.write(Data("\n".utf8))
            }
            try handle.close()
        } catch let writeError {
            do {
                try handle.close()
            } catch let closeError {
                throw WriteError.closeFailedAfterWriteError(writeError: writeError, closeError: closeError)
            }
            throw writeError
        }

        return directory
    }

    private func buildRecords(
        from log: SimulationLog,
        terminalFacts: ScenarioTerminalFacts
    ) -> [TrainingDatasetRecord] {
        let filledDriveIntents = filledDriveIntents(for: log.events)
        return log.events.enumerated().map { index, event in
            let isLast = index == log.events.index(before: log.events.endIndex)
            let sensors = event.sensorSamples.map { sample in
                TrainingSensorSample(
                    channelIndex: sample.channelIndex,
                    value: sample.value,
                    timestamp: sample.timestamp
                )
            }
            let reflex = event.reflexCorrections.map { correction in
                TrainingReflexCorrection(
                    driveIndex: correction.driveIndex.rawValue,
                    clamp: correction.clampMultiplier,
                    damping: correction.damping,
                    delta: correction.delta
                )
            }
            return TrainingDatasetRecord(
                time: event.time.time,
                sensors: sensors,
                driveIntents: filledDriveIntents[index],
                reflexCorrections: reflex,
                continueValue: isLast ? 0.0 : 1.0,
                done: isLast ? terminalFacts.done : false,
                truncated: isLast ? terminalFacts.truncated : false
            )
        }
    }

    private func buildRecords(from episode: RolloutEpisode) -> [TrainingDatasetRecord] {
        let logs = episode.steps.map(\.log)
        let filledDriveIntents = filledDriveIntents(for: logs)
        return episode.steps.enumerated().map { index, step in
            let event = step.log
            let sensors = event.sensorSamples.map { sample in
                TrainingSensorSample(
                    channelIndex: sample.channelIndex,
                    value: sample.value,
                    timestamp: sample.timestamp
                )
            }
            let reflex = event.reflexCorrections.map { correction in
                TrainingReflexCorrection(
                    driveIndex: correction.driveIndex.rawValue,
                    clamp: correction.clampMultiplier,
                    damping: correction.damping,
                    delta: correction.delta
                )
            }
            return TrainingDatasetRecord(
                time: event.time.time,
                sensors: sensors,
                driveIntents: filledDriveIntents[index],
                reflexCorrections: reflex,
                physicsState: physicsPredictionState(for: index, in: episode.steps),
                actualState: stateVector(from: step.observation.plantState),
                actionValues: actionValues(from: event),
                continueValue: (step.done || step.truncated) ? 0.0 : 1.0,
                reward: step.reward,
                done: step.done,
                truncated: step.truncated,
                episodeId: episode.episodeId,
                policyId: episode.policyId
            )
        }
    }

    private func filledDriveIntents(for events: [WorldStepLog]) -> [[TrainingDriveIntent]] {
        let rawDriveIntents = events.map { event in
            driveIntents(from: event)
        }

        guard let firstNonEmptyIndex = rawDriveIntents.firstIndex(where: { !$0.isEmpty }) else {
            return rawDriveIntents
        }

        var filled = rawDriveIntents
        var lastDriveIntents = rawDriveIntents[firstNonEmptyIndex]
        for index in filled.indices {
            if filled[index].isEmpty {
                filled[index] = lastDriveIntents
            } else {
                lastDriveIntents = filled[index]
            }
        }
        return filled
    }

    private func maxChannelCount(_ records: [TrainingDatasetRecord]) -> Int {
        let maxIndex = records.flatMap { $0.sensors }.map { Int($0.channelIndex) }.max() ?? -1
        return maxIndex + 1
    }

    private func maxDriveCount(_ records: [TrainingDatasetRecord]) -> Int {
        let maxIndex = records.flatMap { $0.driveIntents }.map { Int($0.driveIndex) }.max() ?? -1
        return maxIndex + 1
    }

    private func driveIntents(from event: WorldStepLog) -> [TrainingDriveIntent] {
        if !event.driveIntents.isEmpty {
            return event.driveIntents.map { intent in
                TrainingDriveIntent(
                    driveIndex: intent.index.rawValue,
                    value: intent.activation,
                    parameters: intent.parameters
                )
            }
        }

        return event.actuatorValues
            .sorted { $0.index.rawValue < $1.index.rawValue }
            .map { value in
                TrainingDriveIntent(
                    driveIndex: value.index.rawValue,
                    value: value.value,
                    parameters: []
                )
            }
    }

    private func stateVector(from snapshot: PlantStateSnapshot) -> [Double] {
        let root = snapshot.root
        return [
            root.position.x,
            root.position.y,
            root.position.z,
            root.velocity.x,
            root.velocity.y,
            root.velocity.z,
            root.orientation.w,
            root.orientation.x,
            root.orientation.y,
            root.orientation.z,
            root.angularVelocity.x,
            root.angularVelocity.y,
            root.angularVelocity.z,
        ]
    }

    private func physicsPredictionState(for index: Int, in steps: [EnvironmentStep]) -> [Double] {
        guard index > 0, steps.indices.contains(index), steps.indices.contains(index - 1) else {
            return stateVector(from: steps[index].observation.plantState)
        }
        let previous = steps[index - 1]
        let current = steps[index]
        let dt = max(0.0, current.observation.time.time - previous.observation.time.time)
        return predictedStateVector(
            from: previous.observation.plantState,
            dt: dt
        )
    }

    private func predictedStateVector(from snapshot: PlantStateSnapshot, dt: Double) -> [Double] {
        let root = snapshot.root
        return [
            root.position.x + root.velocity.x * dt,
            root.position.y + root.velocity.y * dt,
            root.position.z + root.velocity.z * dt,
            root.velocity.x,
            root.velocity.y,
            root.velocity.z,
            root.orientation.w,
            root.orientation.x,
            root.orientation.y,
            root.orientation.z,
            root.angularVelocity.x,
            root.angularVelocity.y,
            root.angularVelocity.z,
        ]
    }

    private func actionValues(from event: WorldStepLog) -> [Double] {
        if !event.actuatorValues.isEmpty {
            return event.actuatorValues
                .sorted { $0.index.rawValue < $1.index.rawValue }
                .map(\.value)
        }
        return event.driveIntents
            .sorted { $0.index.rawValue < $1.index.rawValue }
            .map(\.activation)
    }
}
