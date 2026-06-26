import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public struct LiftRecoveryRelabelConfig: Sendable, Equatable {
    public let includeOnlyFailedScenarios: Bool
    public let hoverThrustScale: Double
    public let kp: Double
    public let kd: Double

    public init(
        includeOnlyFailedScenarios: Bool = true,
        hoverThrustScale: Double = 1.0,
        kp: Double = 6.0,
        kd: Double = 4.0
    ) {
        self.includeOnlyFailedScenarios = includeOnlyFailedScenarios
        self.hoverThrustScale = hoverThrustScale
        self.kp = kp
        self.kd = kd
    }
}

public struct LiftRecoveryRelabelResult: Sendable, Equatable {
    public let entries: [ScenarioLogEntry]
    public let report: RecoveryRelabelReport

    public init(entries: [ScenarioLogEntry], report: RecoveryRelabelReport) {
        self.entries = entries
        self.report = report
    }
}

public struct LiftRecoveryRelabeler: Sendable {
    public enum RelabelError: Error, Sendable, Equatable {
        case missingDefinition(ScenarioKey)
        case missingLiftEnvelope(ScenarioKey)
        case invalidMaxThrust
    }

    public init() {}

    public func relabel(
        entries: [ScenarioLogEntry],
        definitions: [ReferenceQuadrotorScenarioDefinition],
        parameters: ReferenceQuadrotorParameters,
        config: LiftRecoveryRelabelConfig = LiftRecoveryRelabelConfig()
    ) throws -> LiftRecoveryRelabelResult {
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

        return LiftRecoveryRelabelResult(
            entries: relabeledEntries,
            report: RecoveryRelabelReport(
                sourceEntryCount: entries.count,
                relabeledEntryCount: relabeledEntries.count,
                relabeledStepCount: relabeledStepCount,
                relabeledCutStepCount: relabeledCutStepCount,
                skippedEntryCount: skippedEntryCount
            )
        )
    }

    public func write(
        result: LiftRecoveryRelabelResult,
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
        config: LiftRecoveryRelabelConfig
    ) throws -> ScenarioLogEntry {
        guard parameters.maxThrust > 0, parameters.maxThrust.isFinite else {
            throw RelabelError.invalidMaxThrust
        }
        let relabeledEvents = try entry.log.events.map { event in
            try relabel(event: event, targetZ: targetZ, parameters: parameters, config: config)
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
        targetZ: Double,
        parameters: ReferenceQuadrotorParameters,
        config: LiftRecoveryRelabelConfig
    ) throws -> WorldStepLog {
        let shouldRelabel = event.events.contains(.cutUpdate) || !event.driveIntents.isEmpty
        let drives: [DriveIntent]
        if shouldRelabel {
            drives = try teacherDrives(
                plantState: event.plantState,
                targetZ: targetZ,
                parameters: parameters,
                config: config
            )
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

    private func teacherDrives(
        plantState: PlantStateSnapshot,
        targetZ: Double,
        parameters: ReferenceQuadrotorParameters,
        config: LiftRecoveryRelabelConfig
    ) throws -> [DriveIntent] {
        let z = plantState.root.position.z
        let vz = plantState.root.velocity.z
        let hoverThrust = parameters.mass * parameters.gravity / 4.0 * config.hoverThrustScale
        let error = targetZ - z
        let desiredThrust = hoverThrust + config.kp * error - config.kd * vz
        let throttle = clamp(desiredThrust / max(parameters.maxThrust, 1e-6), lower: 0.0, upper: 1.0)
        return try [
            DriveIntent(index: DriveIndex(0), activation: throttle, parameters: []),
            DriveIntent(index: DriveIndex(1), activation: 0.0, parameters: []),
            DriveIntent(index: DriveIndex(2), activation: 0.0, parameters: []),
            DriveIntent(index: DriveIndex(3), activation: 0.0, parameters: []),
        ]
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
