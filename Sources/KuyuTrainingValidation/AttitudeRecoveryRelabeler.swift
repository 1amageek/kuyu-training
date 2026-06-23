import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public struct AttitudeRecoveryRelabelConfig: Sendable, Equatable {
    public let includeOnlyFailedScenarios: Bool
    public let teacherConfig: PrivilegedAltitudeHoldTeacherConfig

    public init(
        includeOnlyFailedScenarios: Bool = true,
        teacherConfig: PrivilegedAltitudeHoldTeacherConfig = .activeAltitudeHold
    ) {
        self.includeOnlyFailedScenarios = includeOnlyFailedScenarios
        self.teacherConfig = teacherConfig
    }

    public var policyId: String {
        "teacherActiveAltitudeHoldRelabel"
    }
}

public struct AttitudeRecoveryRelabelReport: Sendable, Codable, Equatable {
    public let sourceEntryCount: Int
    public let relabeledEntryCount: Int
    public let relabeledStepCount: Int
    public let relabeledCutStepCount: Int
    public let skippedEntryCount: Int

    public init(
        sourceEntryCount: Int,
        relabeledEntryCount: Int,
        relabeledStepCount: Int,
        relabeledCutStepCount: Int,
        skippedEntryCount: Int
    ) {
        self.sourceEntryCount = sourceEntryCount
        self.relabeledEntryCount = relabeledEntryCount
        self.relabeledStepCount = relabeledStepCount
        self.relabeledCutStepCount = relabeledCutStepCount
        self.skippedEntryCount = skippedEntryCount
    }
}

public struct AttitudeRecoveryRelabelResult: Sendable, Equatable {
    public let entries: [ScenarioLogEntry]
    public let report: AttitudeRecoveryRelabelReport
    public let policyId: String

    public init(
        entries: [ScenarioLogEntry],
        report: AttitudeRecoveryRelabelReport,
        policyId: String = "teacherActiveAltitudeHoldRelabel"
    ) {
        self.entries = entries
        self.report = report
        self.policyId = policyId
    }
}

public struct AttitudeRecoveryRelabeler: Sendable {
    public enum RelabelError: Error, Sendable, Equatable {
        case missingDefinition(ScenarioKey)
    }

    public init() {}

    public func relabel(
        entries: [ScenarioLogEntry],
        definitions: [ReferenceQuadrotorScenarioDefinition],
        parameters: ReferenceQuadrotorParameters,
        gains: ImuRateDampingCutGains,
        config: AttitudeRecoveryRelabelConfig = AttitudeRecoveryRelabelConfig()
    ) throws -> AttitudeRecoveryRelabelResult {
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
            let relabeled = try relabel(
                entry: entry,
                definition: definition,
                parameters: parameters,
                gains: gains,
                config: config
            )
            relabeledStepCount += relabeled.log.events.count
            relabeledCutStepCount += relabeled.log.events.filter { !$0.driveIntents.isEmpty }.count
            relabeledEntries.append(relabeled)
        }

        return AttitudeRecoveryRelabelResult(
            entries: relabeledEntries,
            report: AttitudeRecoveryRelabelReport(
                sourceEntryCount: entries.count,
                relabeledEntryCount: relabeledEntries.count,
                relabeledStepCount: relabeledStepCount,
                relabeledCutStepCount: relabeledCutStepCount,
                skippedEntryCount: skippedEntryCount
            ),
            policyId: config.policyId
        )
    }

    public func write(
        result: AttitudeRecoveryRelabelResult,
        to directory: URL
    ) throws -> [ScenarioKey: URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result.report).write(
            to: directory.appendingPathComponent("recovery-relabel-report.json"),
            options: [.atomic]
        )
        // The relabeled actions are the teacher's, not the rolled-out policy's, so
        // stamp the dataset's provenance as a teacher relabel. The CTBR dataset
        // loader gates on a "teacher"/"ctbr" policyId; without this the relabeled
        // dataset would be rejected by profile validation even though its driveIntents
        // are the normalized teacher activation it expects.
        return try TrainingDatasetExporter().write(
            entries: result.entries,
            to: directory,
            policyId: result.policyId
        )
    }

    private func relabel(
        entry: ScenarioLogEntry,
        definition: ReferenceQuadrotorScenarioDefinition,
        parameters: ReferenceQuadrotorParameters,
        gains: ImuRateDampingCutGains,
        config: AttitudeRecoveryRelabelConfig
    ) throws -> ScenarioLogEntry {
        var teacher = try makeTeacher(
            definition: definition,
            parameters: parameters,
            gains: gains,
            config: config
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

    public func relabel(
        event: WorldStepLog,
        teacher: inout KuyAtt1PrivilegedAltitudeHoldTeacher
    ) throws -> WorldStepLog {
        let shouldRelabel = event.events.contains(.cutUpdate) || !event.driveIntents.isEmpty
        let drives: [DriveIntent]
        if shouldRelabel {
            drives = try teacher.driveIntents(for: event)
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

    public func makeTeacher(
        definition: ReferenceQuadrotorScenarioDefinition,
        parameters: ReferenceQuadrotorParameters,
        gains: ImuRateDampingCutGains,
        config: AttitudeRecoveryRelabelConfig
    ) throws -> KuyAtt1PrivilegedAltitudeHoldTeacher {
        try KuyAtt1PrivilegedAltitudeHoldTeacher(
            definition: definition,
            parameters: parameters,
            gains: gains,
            config: config.teacherConfig
        )
    }
}
