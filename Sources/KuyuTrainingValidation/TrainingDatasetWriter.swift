import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

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
        try resolvedTerminalFacts.validate()
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

}
