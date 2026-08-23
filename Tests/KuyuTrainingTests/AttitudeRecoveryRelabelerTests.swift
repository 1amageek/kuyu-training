import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTraining
import Foundation
import Testing

@Test func attitudeRecoveryRelabelerReplacesPolicyDrivesWithTeacherDrives() throws {
    let definition = try makeRecoveryDefinition()
    let entry = try makeRecoveryEntry(definition: definition, failed: true)

    let result = try AttitudeRecoveryRelabeler().relabel(
        entries: [entry],
        definitions: [definition],
        parameters: .baseline,
        gains: try ImuRateDampingCutGains(kp: 6.0, kd: 4.0, yawDamping: 0.4, hoverThrustScale: 1.0)
    )

    #expect(result.report.sourceEntryCount == 1)
    #expect(result.report.relabeledEntryCount == 1)
    #expect(result.report.relabeledCutStepCount == 1)
    #expect(result.policyId == "teacherActiveAltitudeHoldRelabel")
    let drives = try #require(result.entries.first?.log.events.first?.driveIntents)
    #expect(drives.count == 4)
    #expect(drives[0].activation > 0.0)
    #expect(drives[0].activation != 0.01)
}

@Test func attitudeRecoveryRelabelerUsesActiveAltitudeTeacherByDefault() throws {
    let definition = try makeRecoveryDefinition()
    let lowEntry = try makeRecoveryEntry(
        definition: definition,
        failed: true,
        altitude: definition.initialPosition.z - 0.25,
        verticalVelocity: 0
    )
    let referenceEntry = try makeRecoveryEntry(
        definition: definition,
        failed: true,
        altitude: definition.initialPosition.z,
        verticalVelocity: 0
    )
    let gains = try ImuRateDampingCutGains(kp: 6.0, kd: 4.0, yawDamping: 0.4, hoverThrustScale: 1.0)
    let low = try AttitudeRecoveryRelabeler().relabel(
        entries: [lowEntry],
        definitions: [definition],
        parameters: .baseline,
        gains: gains
    )
    let reference = try AttitudeRecoveryRelabeler().relabel(
        entries: [referenceEntry],
        definitions: [definition],
        parameters: .baseline,
        gains: gains
    )

    let lowThrottle = try #require(low.entries.first?.log.events.first?.driveIntents.first?.activation)
    let referenceThrottle = try #require(reference.entries.first?.log.events.first?.driveIntents.first?.activation)
    #expect(low.policyId == "teacherActiveAltitudeHoldRelabel")
    #expect(lowThrottle > referenceThrottle)
}

@Test func attitudeRecoveryRelabelerSkipsSuccessfulScenariosByDefault() throws {
    let definition = try makeRecoveryDefinition()
    let entry = try makeRecoveryEntry(definition: definition, failed: false)

    let result = try AttitudeRecoveryRelabeler().relabel(
        entries: [entry],
        definitions: [definition],
        parameters: .baseline,
        gains: try ImuRateDampingCutGains(kp: 6.0, kd: 4.0, yawDamping: 0.4, hoverThrustScale: 1.0)
    )

    #expect(result.entries.isEmpty)
    #expect(result.report.skippedEntryCount == 1)
}

@Test func attitudeRecoveryRelabelerWritesLoadableDatasetArtifacts() throws {
    let definition = try makeRecoveryDefinition()
    let entry = try makeRecoveryEntry(definition: definition, failed: true)
    let relabeler = AttitudeRecoveryRelabeler()
    let result = try relabeler.relabel(
        entries: [entry],
        definitions: [definition],
        parameters: .baseline,
        gains: try ImuRateDampingCutGains(kp: 6.0, kd: 4.0, yawDamping: 0.4, hoverThrustScale: 1.0)
    )
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-recovery-relabel-\(UUID().uuidString)", isDirectory: true)

    let outputs = try relabeler.write(result: result, to: directory)

    let datasetURL = try #require(outputs[entry.key])
    let dataset = try TrainingDataset.load(from: datasetURL)
    #expect(dataset.metadata.recordCount == 2)
    #expect(dataset.records.first?.driveIntents.count == 4)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("recovery-relabel-report.json").path))
}

@Test func attitudeRecoveryRelabelerRelabelsRolloutEpisodePreservingTrainingSignal() throws {
    let definition = try makeRecoveryDefinition()
    let lowEpisode = try makeRecoveryEpisode(
        definition: definition,
        altitude: definition.initialPosition.z - 0.25,
        verticalVelocity: -0.06
    )
    let referenceEpisode = try makeRecoveryEpisode(
        definition: definition,
        altitude: definition.initialPosition.z,
        verticalVelocity: 0
    )
    let gains = try ImuRateDampingCutGains(kp: 6.0, kd: 4.0, yawDamping: 0.4, hoverThrustScale: 1.0)
    let relabeler = AttitudeRecoveryRelabeler()

    let low = try relabeler.relabelEpisode(
        lowEpisode,
        definition: definition,
        parameters: .baseline,
        gains: gains
    )
    let reference = try relabeler.relabelEpisode(
        referenceEpisode,
        definition: definition,
        parameters: .baseline,
        gains: gains
    )

    let lowThrottle = try #require(low.steps.first?.log.driveIntents.first?.activation)
    let referenceThrottle = try #require(reference.steps.first?.log.driveIntents.first?.activation)
    #expect(low.policyId == "teacherActiveAltitudeHoldRelabel")
    #expect(lowThrottle > referenceThrottle)
    #expect(low.rewardSum == lowEpisode.rewardSum)
    #expect(low.steps.first?.reward == lowEpisode.steps.first?.reward)
    #expect(low.steps.first?.observation == lowEpisode.steps.first?.observation)
    #expect(low.terminalReason == lowEpisode.terminalReason)

    let dataset = TrainingDatasetWriter().makeDataset(
        episode: low,
        timeStep: definition.config.timeStep.delta,
        determinismTier: "tier0"
    )
    #expect(dataset.metadata.policyId == "teacherActiveAltitudeHoldRelabel")
    #expect(dataset.records.first?.reward == lowEpisode.steps.first?.reward)
    #expect(dataset.records.first?.actualState?.count == 13)
    #expect(dataset.records.first?.driveIntents.count == 4)
}

@Test func attitudeRecoveryRelabelerRelabelsTailAfterPrefixWarmup() throws {
    let definition = try makeRecoveryDefinition()
    let episode = try makeRecoveryEpisode(
        definition: definition,
        altitude: definition.initialPosition.z - 0.25,
        verticalVelocity: -0.06,
        stepCount: 4
    )
    let gains = try ImuRateDampingCutGains(kp: 6.0, kd: 4.0, yawDamping: 0.4, hoverThrustScale: 1.0)

    let relabeled = try AttitudeRecoveryRelabeler().relabelEpisode(
        episode,
        definition: definition,
        parameters: .baseline,
        gains: gains,
        startIndex: 2
    )

    let expectedRewardSum = episode.steps.suffix(2).map(\.reward).reduce(0, +)
    #expect(relabeled.policyId == "teacherActiveAltitudeHoldRelabel")
    #expect(relabeled.steps.count == 2)
    #expect(relabeled.stepCount == 2)
    #expect(relabeled.rewardSum == expectedRewardSum)
    #expect(relabeled.steps.first?.log.time == episode.steps[2].log.time)
    #expect(relabeled.steps.first?.observation == episode.steps[2].observation)
    #expect(relabeled.steps.first?.log.driveIntents.count == 4)
}

private func makeRecoveryDefinition() throws -> ReferenceQuadrotorScenarioDefinition {
    let scenarios = try KuyAtt1Suite().scenarios()
    return try #require(scenarios.first)
}

private func makeRecoveryEntry(
    definition: ReferenceQuadrotorScenarioDefinition,
    failed: Bool,
    altitude: Double? = nil,
    verticalVelocity: Double = 0
) throws -> ScenarioLogEntry {
    let z = altitude ?? definition.initialPosition.z
    let events = try [
        makeRecoveryStep(stepIndex: 0, includeCutUpdate: true, altitude: z, verticalVelocity: verticalVelocity),
        makeRecoveryStep(stepIndex: 1, includeCutUpdate: false, altitude: z, verticalVelocity: verticalVelocity),
    ]
    let log = try SimulationLog(
        scenarioId: definition.config.id,
        seed: definition.config.seed,
        timeStep: TimeStep(delta: 0.01),
        determinism: DeterminismConfig(tier: .tier0, tier1Tolerance: nil),
        configHash: "recovery-test",
        events: events,
        failureReason: failed ? .sustainedFall : nil,
        failureTime: failed ? 0.01 : nil
    )
    return ScenarioLogEntry(
        key: ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed),
        log: log
    )
}

private func makeRecoveryEpisode(
    definition: ReferenceQuadrotorScenarioDefinition,
    altitude: Double,
    verticalVelocity: Double,
    stepCount: Int = 2
) throws -> RolloutEpisode {
    let count = max(1, stepCount)
    let logs = try (0..<count).map { index in
        try makeRecoveryStep(
            stepIndex: UInt64(index),
            includeCutUpdate: true,
            altitude: altitude,
            verticalVelocity: verticalVelocity
        )
    }
    let steps = try logs.enumerated().map { index, log in
        try EnvironmentStep(
            observation: EnvironmentObservation(log: log),
            reward: index == 0 ? 0.5 : -1.0,
            done: index == logs.count - 1,
            truncated: false,
            info: EpisodeInfo(
                scenarioId: definition.config.id,
                seed: definition.config.seed,
                configHash: "recovery-episode-test",
                stepCount: index + 1,
                rewardSum: -0.5,
                terminalReason: "sustained-fall"
            ),
            log: log
        )
    }
    return RolloutEpisode(
        episodeId: "recovery-episode-test",
        scenarioId: definition.config.id.rawValue,
        seed: definition.config.seed.rawValue,
        workerIndex: 0,
        policyId: "manasMojo-policy",
        configHash: "recovery-episode-test",
        robotManifestID: nil,
        rewardSum: -0.5,
        done: true,
        truncated: false,
        terminalReason: "sustained-fall",
        failureReason: "sustained-fall",
        failureTime: logs.last?.time.time,
        stepCount: steps.count,
        durationSeconds: logs.last?.time.time ?? 0,
        steps: steps
    )
}

private func makeRecoveryStep(
    stepIndex: UInt64,
    includeCutUpdate: Bool,
    altitude: Double = 2,
    verticalVelocity: Double = 0
) throws -> WorldStepLog {
    try WorldStepLog(
        time: WorldTime(stepIndex: stepIndex, time: Double(stepIndex) * 0.01),
        events: includeCutUpdate ? [.timeAdvance, .cutUpdate] : [.timeAdvance],
        sensorSamples: [
            ChannelSample(channelIndex: 0, value: 0.0, timestamp: Double(stepIndex) * 0.01),
            ChannelSample(channelIndex: 1, value: 0.0, timestamp: Double(stepIndex) * 0.01),
            ChannelSample(channelIndex: 2, value: 0.0, timestamp: Double(stepIndex) * 0.01),
            ChannelSample(channelIndex: 3, value: 0.0, timestamp: Double(stepIndex) * 0.01),
            ChannelSample(channelIndex: 4, value: 0.0, timestamp: Double(stepIndex) * 0.01),
            ChannelSample(channelIndex: 5, value: 1.0, timestamp: Double(stepIndex) * 0.01),
        ],
        driveIntents: includeCutUpdate
            ? [DriveIntent(index: DriveIndex(0), activation: 0.01, parameters: [])]
            : [],
        reflexCorrections: [],
        actuatorValues: [],
        actuatorTelemetry: ActuatorTelemetrySnapshot(channels: []),
        safetyTrace: SafetyTrace(omegaMagnitude: 0.0, tiltRadians: 0.0),
        plantState: PlantStateSnapshot(
            root: RigidBodySnapshot(
                id: "root",
                position: Axis3(x: 0, y: 0, z: altitude),
                velocity: Axis3(x: 0, y: 0, z: verticalVelocity),
                orientation: QuaternionSnapshot(w: 1, x: 0, y: 0, z: 0),
                angularVelocity: Axis3(x: 0, y: 0, z: 0)
            )
        ),
        disturbances: DisturbanceSnapshot(
            forceWorld: Axis3(x: 0, y: 0, z: 0),
            torqueBody: Axis3(x: 0, y: 0, z: 0)
        )
    )
}
