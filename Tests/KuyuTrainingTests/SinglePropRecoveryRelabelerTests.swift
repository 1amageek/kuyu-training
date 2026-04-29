import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTraining
import Testing

@Test func singlePropRecoveryRelabelerReplacesFailedPolicyDriveWithTeacherDrive() throws {
    let definition = try makeSinglePropRecoveryDefinition()
    let entry = try makeSinglePropRecoveryEntry(definition: definition, failed: true)

    let result = try SinglePropRecoveryRelabeler().relabel(
        entries: [entry],
        definitions: [definition],
        parameters: .baseline,
        config: SinglePropRecoveryRelabelConfig(hoverThrustScale: 1.0)
    )

    #expect(result.report.sourceEntryCount == 1)
    #expect(result.report.relabeledEntryCount == 1)
    #expect(result.report.relabeledCutStepCount == 1)
    let drives = try #require(result.entries.first?.log.events.first?.driveIntents)
    #expect(drives.count == 1)
    #expect(drives[0].activation > 0.01)
}

@Test func singlePropRecoveryRelabelerWritesLoadableDatasetArtifacts() throws {
    let definition = try makeSinglePropRecoveryDefinition()
    let entry = try makeSinglePropRecoveryEntry(definition: definition, failed: true)
    let relabeler = SinglePropRecoveryRelabeler()
    let result = try relabeler.relabel(
        entries: [entry],
        definitions: [definition],
        parameters: .baseline,
        config: SinglePropRecoveryRelabelConfig(hoverThrustScale: 1.0)
    )
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-single-prop-recovery-relabel-\(UUID().uuidString)", isDirectory: true)

    let outputs = try relabeler.write(result: result, to: directory)

    let datasetURL = try #require(outputs[entry.key])
    let dataset = try TrainingDataset.load(from: datasetURL)
    #expect(dataset.metadata.recordCount == 2)
    #expect(dataset.records.first?.driveIntents.count == 1)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("recovery-relabel-report.json").path))
}

@Test func singlePropRecoveryRelabelerCanIncludeSuccessfulScenariosForCorrection() throws {
    let definition = try makeSinglePropRecoveryDefinition()
    let entry = try makeSinglePropRecoveryEntry(definition: definition, failed: false)

    let result = try SinglePropRecoveryRelabeler().relabel(
        entries: [entry],
        definitions: [definition],
        parameters: .baseline,
        config: SinglePropRecoveryRelabelConfig(
            includeOnlyFailedScenarios: false,
            hoverThrustScale: 1.0
        )
    )

    #expect(result.report.sourceEntryCount == 1)
    #expect(result.report.relabeledEntryCount == 1)
    #expect(result.report.skippedEntryCount == 0)
}

private func makeSinglePropRecoveryDefinition() throws -> ReferenceQuadrotorScenarioDefinition {
    let scenarios = try KuySingleLiftSuite().scenarios()
    return try #require(scenarios.first)
}

private func makeSinglePropRecoveryEntry(
    definition: ReferenceQuadrotorScenarioDefinition,
    failed: Bool
) throws -> ScenarioLogEntry {
    let targetZ = try #require(definition.liftEnvelope?.targetZ)
    let events = try [
        makeSinglePropRecoveryStep(stepIndex: 0, altitudeZ: targetZ - 0.5, includeCutUpdate: true),
        makeSinglePropRecoveryStep(stepIndex: 1, altitudeZ: targetZ - 0.4, includeCutUpdate: false),
    ]
    let log = try SimulationLog(
        scenarioId: definition.config.id,
        seed: definition.config.seed,
        timeStep: TimeStep(delta: 0.01),
        determinism: DeterminismConfig(tier: .tier0, tier1Tolerance: nil),
        configHash: "single-prop-recovery-test",
        events: events,
        failureReason: failed ? .sustainedFall : nil,
        failureTime: failed ? 0.01 : nil
    )
    return ScenarioLogEntry(
        key: ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed),
        log: log
    )
}

private func makeSinglePropRecoveryStep(
    stepIndex: UInt64,
    altitudeZ: Double,
    includeCutUpdate: Bool
) throws -> WorldStepLog {
    try WorldStepLog(
        time: WorldTime(stepIndex: stepIndex, time: Double(stepIndex) * 0.01),
        events: includeCutUpdate ? [.timeAdvance, .cutUpdate] : [.timeAdvance],
        sensorSamples: [
            ChannelSample(channelIndex: 6, value: altitudeZ, timestamp: Double(stepIndex) * 0.01),
            ChannelSample(channelIndex: 7, value: 0.0, timestamp: Double(stepIndex) * 0.01),
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
                velocity: Axis3(x: 0, y: 0, z: 0),
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
