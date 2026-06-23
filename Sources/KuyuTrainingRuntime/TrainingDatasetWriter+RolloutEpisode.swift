import Foundation
import KuyuCore
import KuyuPhysics
import KuyuTrainingValidation

public extension TrainingDatasetWriter {
    func write(
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

    func makeDataset(
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
