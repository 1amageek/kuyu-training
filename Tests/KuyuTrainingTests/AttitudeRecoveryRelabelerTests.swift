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
