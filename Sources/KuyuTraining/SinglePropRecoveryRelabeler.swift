import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios

public struct SinglePropRecoveryRelabelConfig: Sendable, Equatable {
    public let includeOnlyFailedScenarios: Bool
    public let hoverThrustScale: Double

    public init(
        includeOnlyFailedScenarios: Bool = true,
        hoverThrustScale: Double = 1.0
    ) {
        self.includeOnlyFailedScenarios = includeOnlyFailedScenarios
        self.hoverThrustScale = hoverThrustScale
    }
}

public struct SinglePropRecoveryRelabelResult: Sendable, Equatable {
    public let entries: [ScenarioLogEntry]
    public let report: AttitudeRecoveryRelabelReport

    public init(entries: [ScenarioLogEntry], report: AttitudeRecoveryRelabelReport) {
        self.entries = entries
        self.report = report
    }
}

public struct SinglePropRecoveryRelabeler: Sendable {
    public enum RelabelError: Error, Sendable, Equatable {
        case missingDefinition(ScenarioKey)
        case missingLiftEnvelope(ScenarioKey)
    }

    public init() {}

    public func relabel(
        entries: [ScenarioLogEntry],
        definitions: [ReferenceQuadrotorScenarioDefinition],
        parameters: ReferenceQuadrotorParameters,
        config: SinglePropRecoveryRelabelConfig = SinglePropRecoveryRelabelConfig()
    ) throws -> SinglePropRecoveryRelabelResult {
        let definitionByKey = Dictionary(
            uniqueKeysWithValues: definitions.map {
                (ScenarioKey(scenarioId: $0.config.id, seed: $0.config.seed), $0)
            }
        )
        var relabeledEntries: [ScenarioLogEntry] = []
        relabeledEntries.reserveCapacity(entries.count)
        var relabeledStepCount = 0
        var relabeledCutStepCount = 0
        var skippedEntryCount = 0

        for entry in entries {
            if config.includeOnlyFailedScenarios, entry.log.failureReason == nil {
                skippedEntryCount += 1
                continue
            }
            guard let definition = definitionByKey[entry.key] else {
                throw RelabelError.missingDefinition(entry.key)
            }
            guard let liftEnvelope = definition.liftEnvelope else {
                throw RelabelError.missingLiftEnvelope(entry.key)
            }
            let relabeled = try relabel(
                entry: entry,
                targetZ: liftEnvelope.targetZ,
                parameters: parameters,
                config: config
            )
            relabeledStepCount += relabeled.log.events.count
            relabeledCutStepCount += relabeled.log.events.filter { !$0.driveIntents.isEmpty }.count
            relabeledEntries.append(relabeled)
        }

        return SinglePropRecoveryRelabelResult(
            entries: relabeledEntries,
            report: AttitudeRecoveryRelabelReport(
                sourceEntryCount: entries.count,
                relabeledEntryCount: relabeledEntries.count,
                relabeledStepCount: relabeledStepCount,
                relabeledCutStepCount: relabeledCutStepCount,
                skippedEntryCount: skippedEntryCount
            )
        )
    }

    public func write(
        result: SinglePropRecoveryRelabelResult,
        to directory: URL
    ) throws -> [ScenarioKey: URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result.report).write(
            to: directory.appendingPathComponent("recovery-relabel-report.json"),
            options: [.atomic]
        )
        return try TrainingDatasetExporter().write(entries: result.entries, to: directory)
    }

    private func relabel(
        entry: ScenarioLogEntry,
        targetZ: Double,
        parameters: ReferenceQuadrotorParameters,
        config: SinglePropRecoveryRelabelConfig
    ) throws -> ScenarioLogEntry {
        var teacher = try SinglePropHoverCut(
            targetZ: targetZ,
            hoverThrust: parameters.mass * parameters.gravity * config.hoverThrustScale,
            maxThrust: parameters.maxThrust
        )
        let relabeledEvents = try entry.log.events.map { event in
            try relabel(event: event, teacher: &teacher)
        }
        let log = SimulationLog(
            scenarioId: entry.log.scenarioId,
            seed: entry.log.seed,
            timeStep: entry.log.timeStep,
            determinism: entry.log.determinism,
            configHash: entry.log.configHash,
            events: relabeledEvents,
            failureReason: entry.log.failureReason,
            failureTime: entry.log.failureTime,
            observability: entry.log.observability
        )
        return ScenarioLogEntry(key: entry.key, log: log)
    }

    private func relabel(
        event: WorldStepLog,
        teacher: inout SinglePropHoverCut
    ) throws -> WorldStepLog {
        let shouldRelabel = event.events.contains(.cutUpdate) || !event.driveIntents.isEmpty
        let drives: [DriveIntent]
        if shouldRelabel {
            let output = try teacher.update(samples: event.sensorSamples, time: event.time)
            switch output {
            case .driveIntents(let intents, _):
                drives = intents
            case .actuatorValues:
                drives = []
            }
        } else {
            drives = []
        }
        return WorldStepLog(
            time: event.time,
            events: event.events,
            sensorSamples: event.sensorSamples,
            driveIntents: drives,
            reflexCorrections: [],
            actuatorValues: event.actuatorValues,
            actuatorTelemetry: event.actuatorTelemetry,
            motorNerveTrace: event.motorNerveTrace,
            safetyTrace: event.safetyTrace,
            plantState: event.plantState,
            disturbances: event.disturbances
        )
    }
}
