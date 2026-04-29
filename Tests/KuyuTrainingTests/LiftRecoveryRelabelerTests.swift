import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTraining
import Testing

@Test func liftRecoveryRelabelerProducesFourDriveAltitudeRecoveryLabels() throws {
    let definition = try makeLiftRecoveryDefinition()
    let targetZ = try #require(definition.liftEnvelope?.targetZ)
    let entry = try makeLiftRecoveryEntry(definition: definition, altitudeZ: targetZ - 0.5, velocityZ: -0.8, failed: true)

    let result = try LiftRecoveryRelabeler().relabel(
        entries: [entry],
        definitions: [definition],
        parameters: .baseline,
        config: LiftRecoveryRelabelConfig(hoverThrustScale: 1.0)
    )

    #expect(result.report.sourceEntryCount == 1)
    #expect(result.report.relabeledEntryCount == 1)
    #expect(result.report.relabeledCutStepCount == 1)
    let drives = try #require(result.entries.first?.log.events.first?.driveIntents)
    #expect(drives.count == 4)
    #expect(drives[0].activation > 0.01)
    #expect(drives[1].activation == 0.0)
    #expect(drives[2].activation == 0.0)
    #expect(drives[3].activation == 0.0)
}

@Test func liftRecoveryRelabelerWritesLoadableFourDriveDatasetArtifacts() throws {
    let definition = try makeLiftRecoveryDefinition()
    let targetZ = try #require(definition.liftEnvelope?.targetZ)
    let entry = try makeLiftRecoveryEntry(definition: definition, altitudeZ: targetZ - 0.5, velocityZ: -0.8, failed: true)
    let relabeler = LiftRecoveryRelabeler()
    let result = try relabeler.relabel(
        entries: [entry],
        definitions: [definition],
        parameters: .baseline,
        config: LiftRecoveryRelabelConfig(hoverThrustScale: 1.0)
    )
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-lift-recovery-relabel-\(UUID().uuidString)", isDirectory: true)

    let outputs = try relabeler.write(result: result, to: directory)

    let datasetURL = try #require(outputs[entry.key])
    let dataset = try TrainingDataset.load(from: datasetURL)
    #expect(dataset.metadata.recordCount == 2)
    #expect(dataset.metadata.driveCount == 4)
    #expect(dataset.records.first?.driveIntents.count == 4)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("recovery-relabel-report.json").path))
}

@Test func liftRecoveryRelabelerCanIncludeSuccessfulScenariosForCorrection() throws {
    let definition = try makeLiftRecoveryDefinition()
    let targetZ = try #require(definition.liftEnvelope?.targetZ)
    let entry = try makeLiftRecoveryEntry(definition: definition, altitudeZ: targetZ, velocityZ: 0.0, failed: false)

    let result = try LiftRecoveryRelabeler().relabel(
        entries: [entry],
        definitions: [definition],
        parameters: .baseline,
        config: LiftRecoveryRelabelConfig(includeOnlyFailedScenarios: false)
    )

    #expect(result.report.sourceEntryCount == 1)
    #expect(result.report.relabeledEntryCount == 1)
    #expect(result.report.skippedEntryCount == 0)
}

private func makeLiftRecoveryDefinition() throws -> ReferenceQuadrotorScenarioDefinition {
    let scenarios = try KuyLiftSuite().scenarios()
    return try #require(scenarios.first)
}

private func makeLiftRecoveryEntry(
    definition: ReferenceQuadrotorScenarioDefinition,
    altitudeZ: Double,
    velocityZ: Double,
    failed: Bool
) throws -> ScenarioLogEntry {
    let events = try [
        makeLiftRecoveryStep(stepIndex: 0, altitudeZ: altitudeZ, velocityZ: velocityZ, includeCutUpdate: true),
        makeLiftRecoveryStep(stepIndex: 1, altitudeZ: altitudeZ + 0.1, velocityZ: 0.0, includeCutUpdate: false),
    ]
    let log = try SimulationLog(
        scenarioId: definition.config.id,
        seed: definition.config.seed,
        timeStep: TimeStep(delta: 0.01),
        determinism: DeterminismConfig(tier: .tier0, tier1Tolerance: nil),
        configHash: "lift-recovery-test",
        events: events,
        failureReason: failed ? .sustainedFall : nil,
        failureTime: failed ? 0.01 : nil
    )
    return ScenarioLogEntry(
        key: ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed),
        log: log
    )
}

private func makeLiftRecoveryStep(
    stepIndex: UInt64,
    altitudeZ: Double,
    velocityZ: Double,
    includeCutUpdate: Bool
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
                position: Axis3(x: 0, y: 0, z: altitudeZ),
                velocity: Axis3(x: 0, y: 0, z: velocityZ),
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
