import Foundation
import KuyuCore
import KuyuPhysics
import KuyuTraining
import Testing

@Test func roArmM1ArmGripperBuilderCreatesRewardAwareHindsightDataset() throws {
    let log = try makeRoArmM1JointTargetLog()
    let result = try RoArmM1JointTargetTrainingDatasetBuilder().build(from: log)

    #expect(result.report.status == .achieved)
    #expect(result.report.sourceRecordCount == 2)
    #expect(result.report.hindsightRecordCount == 2)
    #expect(result.report.recordCount == 4)
    #expect(result.report.activeEfficiencyTechniqueIDs.contains("roarm-m1-hindsight-goal-relabeling-v1"))
    #expect(result.dataset.metadata.channelCount == 25)
    #expect(result.dataset.metadata.driveCount == 5)
    #expect(result.dataset.metadata.rewardSum == result.report.rewardSum)
    #expect(result.dataset.metadata.observation?.modalities?.first?.channels?.contains("gripperClampTargetError") == true)
    #expect(result.dataset.records.count == 4)
    #expect(result.dataset.records.allSatisfy { $0.sensors.count == 25 })
    #expect(result.dataset.records.allSatisfy { $0.actionValues?.count == 5 })
    #expect(result.report.perDrive.map(\.driveID) == RoArmM1ArmGripperSemantics.driveIDs)
    let hindsight = result.dataset.records[1]
    let targetErrorChannels = hindsight.sensors.filter { (10...14).contains(Int($0.channelIndex)) }
    #expect(targetErrorChannels.count == 5)
    #expect(targetErrorChannels.allSatisfy { abs($0.value) < 1e-12 })
}

@Test func roArmM1ArmGripperBuilderWritesLoadableArtifacts() throws {
    let log = try makeRoArmM1JointTargetLog()
    let result = try RoArmM1JointTargetTrainingDatasetBuilder().build(from: log)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-roarm-m1-arm-gripper-training-\(UUID().uuidString)", isDirectory: true)

    let output = try RoArmM1JointTargetTrainingDatasetBuilder().write(result: result, to: directory)
    let dataset = try TrainingDataset.load(from: output.appendingPathComponent("dataset", isDirectory: true))

    #expect(dataset.metadata.scenarioId == "ROARM-M1-ARM-GRIPPER-TEST")
    #expect(dataset.records.count == 4)
    #expect(FileManager.default.fileExists(
        atPath: output.appendingPathComponent("roarm-m1-arm-gripper-training-report.json").path
    ))
}

private func makeRoArmM1JointTargetLog() throws -> SimulationLog {
    let events = try [
        makeRoArmM1JointTargetStep(stepIndex: 0, positions: [0, 0, 0, 0, 0], targets: [0.02, 0.01, -0.01, 0.02, -0.02]),
        makeRoArmM1JointTargetStep(stepIndex: 1, positions: [0.03, 0.02, -0.02, 0.03, -0.03], targets: [0.04, 0.03, -0.03, 0.04, -0.04]),
    ]
    return try SimulationLog(
        scenarioId: ScenarioID("ROARM-M1-ARM-GRIPPER-TEST"),
        seed: ScenarioSeed(11),
        timeStep: TimeStep(delta: 0.02),
        determinism: DeterminismConfig(tier: .tier0, tier1Tolerance: nil),
        configHash: "roarm-m1-arm-gripper-test",
        events: events
    )
}

private func makeRoArmM1JointTargetStep(
    stepIndex: UInt64,
    positions: [Double],
    targets: [Double]
) throws -> WorldStepLog {
    var scalars: [String: Double] = [:]
    for index in 0..<RoArmM1ServoCommandEncoder.jointCount {
        let signalID = "joint_\(index + 1)"
        scalars[signalID] = positions[index]
        scalars["target_\(signalID)"] = targets[index]
        scalars["velocity_\(signalID)"] = 0.01
        scalars["torque_\(signalID)"] = 0.02
    }

    return try WorldStepLog(
        time: WorldTime(stepIndex: stepIndex, time: Double(stepIndex) * 0.02),
        events: [.timeAdvance, .cutUpdate, .motorNerveUpdate, .plantIntegrate, .sensorSample],
        sensorSamples: [],
        driveIntents: targets.enumerated().map { index, target in
            try DriveIntent(index: DriveIndex(UInt32(index)), activation: target, parameters: [])
        },
        reflexCorrections: [],
        actuatorValues: targets.enumerated().map { index, target in
            try ActuatorValue(index: ActuatorIndex(UInt32(index)), value: target)
        },
        actuatorTelemetry: ActuatorTelemetrySnapshot(channels: []),
        safetyTrace: SafetyTrace(omegaMagnitude: 0.01, tiltRadians: 0),
        plantState: PlantStateSnapshot(
            root: RigidBodySnapshot(
                id: "roarm-base",
                position: Axis3(x: 0, y: 0, z: 0),
                velocity: Axis3(x: 0, y: 0, z: 0),
                orientation: QuaternionSnapshot(w: 1, x: 0, y: 0, z: 0),
                angularVelocity: Axis3(x: 0, y: 0, z: 0)
            ),
            scalars: scalars
        ),
        disturbances: DisturbanceSnapshot(
            forceWorld: Axis3(x: 0, y: 0, z: 0),
            torqueBody: Axis3(x: 0, y: 0, z: 0)
        )
    )
}
