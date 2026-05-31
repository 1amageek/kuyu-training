import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios

public struct AttitudeRecoveryRelabelConfig: Sendable, Equatable {
    public let includeOnlyFailedScenarios: Bool
    public let baselineMode: KuyAtt1BaselineMode

    public init(
        includeOnlyFailedScenarios: Bool = true,
        baselineMode: KuyAtt1BaselineMode = .teacher
    ) {
        self.includeOnlyFailedScenarios = includeOnlyFailedScenarios
        self.baselineMode = baselineMode
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

    public init(entries: [ScenarioLogEntry], report: AttitudeRecoveryRelabelReport) {
        self.entries = entries
        self.report = report
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
            )
        )
    }

    /// Relabels a full rollout episode (which carries per-step reward + plant
    /// state) with the teacher action, preserving everything except each step's
    /// drive intents. Unlike `relabel(entries:)`, which operates on `ScenarioLog`
    /// entries that have no reward, this keeps the `EnvironmentStep` reward/state
    /// so the written dataset is loadable by the CTBR rollout loader (which
    /// requires per-record reward + actualState). Used by the CTBR DAgger loop:
    /// roll the policy, relabel its visited states with the teacher, behavior-clone
    /// on the aggregate.
    public func relabelEpisode(
        _ episode: RolloutEpisode,
        definition: ReferenceQuadrotorScenarioDefinition,
        parameters: ReferenceQuadrotorParameters,
        gains: ImuRateDampingCutGains,
        config: AttitudeRecoveryRelabelConfig = AttitudeRecoveryRelabelConfig()
    ) throws -> RolloutEpisode {
        var teacher = try makeTeacherCut(
            definition: definition,
            parameters: parameters,
            gains: gains,
            mode: config.baselineMode
        )
        let relabeledSteps = try episode.steps.map { step -> EnvironmentStep in
            let relabeledLog = try relabel(event: step.log, teacher: &teacher)
            return try EnvironmentStep(
                observation: step.observation,
                reward: step.reward,
                done: step.done,
                truncated: step.truncated,
                info: step.info,
                log: relabeledLog
            )
        }
        return RolloutEpisode(
            episodeId: episode.episodeId,
            scenarioId: episode.scenarioId,
            seed: episode.seed,
            workerIndex: episode.workerIndex,
            policyId: "teacherRelabel",
            configHash: episode.configHash,
            robotManifestID: episode.robotManifestID,
            rewardDescriptor: episode.rewardDescriptor,
            rewardSum: episode.rewardSum,
            done: episode.done,
            truncated: episode.truncated,
            terminalReason: episode.terminalReason,
            failureReason: episode.failureReason,
            failureTime: episode.failureTime,
            stepCount: episode.stepCount,
            workerCount: episode.workerCount,
            maxSteps: episode.maxSteps,
            durationSeconds: episode.durationSeconds,
            cancelled: episode.cancelled,
            steps: relabeledSteps,
            taskReference: episode.taskReference
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
        // dataset would be rejected as nonCTBRDataset even though its driveIntents
        // are the normalized teacher activation it expects.
        return try TrainingDatasetExporter().write(
            entries: result.entries,
            to: directory,
            policyId: "teacherRelabel"
        )
    }

    private func relabel(
        entry: ScenarioLogEntry,
        definition: ReferenceQuadrotorScenarioDefinition,
        parameters: ReferenceQuadrotorParameters,
        gains: ImuRateDampingCutGains,
        config: AttitudeRecoveryRelabelConfig
    ) throws -> ScenarioLogEntry {
        var teacher = try makeTeacherCut(
            definition: definition,
            parameters: parameters,
            gains: gains,
            mode: config.baselineMode
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
        teacher: inout ImuRateDampingDriveCut
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

    private func makeTeacherCut(
        definition: ReferenceQuadrotorScenarioDefinition,
        parameters: ReferenceQuadrotorParameters,
        gains: ImuRateDampingCutGains,
        mode: KuyAtt1BaselineMode
    ) throws -> ImuRateDampingDriveCut {
        let hoverThrust = parameters.mass * parameters.gravity / 4.0 * gains.hoverThrustScale
        let initialAttitude: EulerAngles
        let tiltCorrectionTimeConstant: Double?
        switch mode {
        case .teacher:
            initialAttitude = definition.initialAttitude
            tiltCorrectionTimeConstant = nil
        case .sensor:
            initialAttitude = EulerAngles(roll: 0, pitch: 0, yaw: 0)
            tiltCorrectionTimeConstant = 0.4
        }
        return try ImuRateDampingDriveCut(
            hoverThrust: hoverThrust,
            kp: gains.kp,
            kd: gains.kd,
            yawDamping: gains.yawDamping,
            armLength: parameters.armLength,
            yawCoefficient: parameters.yawCoefficient,
            maxThrust: parameters.maxThrust,
            initialRoll: initialAttitude.roll,
            initialPitch: initialAttitude.pitch,
            tiltCorrectionTimeConstant: tiltCorrectionTimeConstant
        )
    }
}
