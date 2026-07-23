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
    #expect(result.dataset.records.allSatisfy { record in
        record.driveIntents.allSatisfy { (-1.0...1.0).contains($0.value) }
    })
    #expect(result.dataset.records.allSatisfy { record in
        record.actionValues?.allSatisfy { (-1.0...1.0).contains($0) } == true
    })
    #expect(result.report.perDrive.map(\.driveID) == RoArmM1ArmGripperSemantics.driveIDs)
    let codec = try JointTargetActionCodec(
        physicalRanges: RoArmM1ServoCommandEncoder.manufacturerJointLimits,
        actionContract: RoArmM1LearningContracts.armGripperTargetsActionContract()
    )
    let firstRecord = try #require(result.dataset.records.first)
    let firstActions = try #require(firstRecord.actionValues)
    let firstTargets = try codec.physicalTargets(fromNormalizedActions: firstActions)
    assertArrayApproximatelyEqual(firstTargets, [0.02, 0.01, -0.01, 0.02, -0.02])
    #expect(firstRecord.driveIntents.map(\.value) == firstActions)
    let hindsight = result.dataset.records[1]
    let targetErrorChannels = hindsight.sensors.filter { (10...14).contains(Int($0.channelIndex)) }
    #expect(targetErrorChannels.count == 5)
    #expect(targetErrorChannels.allSatisfy { abs($0.value) < 1e-12 })
}

@Test func roArmM1ArmGripperBuilderUsesDriveTargetsAndJointScalars() throws {
    let log = try makeRoArmM1JointTargetLog(events: [
        makeRoArmM1MixedDomainStep(
            stepIndex: 0,
            jointPositions: [0.01, 0.02, -0.03, 0.04, -0.05],
            jointTargets: [0.08, 0.2, -0.16, 0.12, -0.1],
            actuatorPositions: [-0.01, -0.06, 0.03, 0.04, 0.05],
            actuatorTargets: [-0.08, -1.4160355717865514, 0.16, 0.12, 0.1]
        )
    ])

    let result = try RoArmM1JointTargetTrainingDatasetBuilder(
        config: RoArmM1JointTargetTrainingDatasetBuilderConfig(includeHindsightRelabels: false)
    ).build(from: log)
    let firstRecord = try #require(result.dataset.records.first)
    let actions = try #require(firstRecord.actionValues)
    let codec = try JointTargetActionCodec(
        physicalRanges: RoArmM1ServoCommandEncoder.manufacturerJointLimits,
        actionContract: RoArmM1LearningContracts.armGripperTargetsActionContract()
    )
    let decodedTargets = try codec.physicalTargets(fromNormalizedActions: actions)

    assertArrayApproximatelyEqual(decodedTargets, [0.08, 0.2, -0.16, 0.12, -0.1])
    #expect(firstRecord.physicsState?.prefix(5).elementsEqual([0.01, 0.02, -0.03, 0.04, -0.05]) == true)
    #expect(result.report.jointLimitViolationCount == 0)
}

@Test func jointTargetActionCodecRoundTripsRoArmM1JointTargets() throws {
    let codec = try JointTargetActionCodec(
        physicalRanges: RoArmM1ServoCommandEncoder.manufacturerJointLimits,
        actionContract: RoArmM1LearningContracts.armGripperTargetsActionContract()
    )
    let physicalTargets = [-3.14, 0.0, 2.7, -2.1, -1.57]

    let normalizedActions = try codec.normalizedActions(fromPhysicalTargets: physicalTargets)
    let decodedTargets = try codec.physicalTargets(fromNormalizedActions: normalizedActions)
    let driveIntents = try codec.driveIntents(fromNormalizedActions: normalizedActions)

    #expect(normalizedActions.allSatisfy { (-1.0...1.0).contains($0) })
    assertArrayApproximatelyEqual(decodedTargets, physicalTargets)
    assertArrayApproximatelyEqual(driveIntents.map(\.activation), physicalTargets)
    #expect(driveIntents.map { Int($0.index.rawValue) } == [0, 1, 2, 3, 4])
}

@Test func jointTargetActionCodecRejectsInvalidActionContractsAndValues() throws {
    let physicalRanges = RoArmM1ServoCommandEncoder.manufacturerJointLimits
    let invalidContract = LearningProjectActionContract(
        schemaID: RoArmM1JointTargetTrainingGoal.canonical.actionSchemaID,
        kind: .continuous,
        driveCount: 5,
        actuatorCount: 5,
        isBounded: true,
        channels: [
            LearningProjectActionChannel(
                index: 0,
                name: "baseYaw",
                unit: "normalized",
                normalizedLowerBound: -1,
                normalizedUpperBound: 1,
                outputTransform: .tanh
            ),
            LearningProjectActionChannel(
                index: 2,
                name: "elbowPitch",
                unit: "normalized",
                normalizedLowerBound: -1,
                normalizedUpperBound: 1,
                outputTransform: .tanh
            ),
            LearningProjectActionChannel(
                index: 3,
                name: "wristPitch",
                unit: "normalized",
                normalizedLowerBound: -1,
                normalizedUpperBound: 1,
                outputTransform: .tanh
            ),
            LearningProjectActionChannel(
                index: 4,
                name: "gripperClamp",
                unit: "normalized",
                normalizedLowerBound: -1,
                normalizedUpperBound: 1,
                outputTransform: .tanh
            ),
            LearningProjectActionChannel(
                index: 5,
                name: "spare",
                unit: "normalized",
                normalizedLowerBound: -1,
                normalizedUpperBound: 1,
                outputTransform: .tanh
            ),
        ]
    )
    #expect(throws: JointTargetActionCodec.CodecError.unsupportedActionContract("non-contiguous-channel-indices")) {
        _ = try JointTargetActionCodec(
            physicalRanges: physicalRanges,
            actionContract: invalidContract
        )
    }

    let codec = try JointTargetActionCodec(
        physicalRanges: physicalRanges,
        actionContract: RoArmM1LearningContracts.armGripperTargetsActionContract()
    )
    #expect(throws: JointTargetActionCodec.CodecError.outOfPhysicalRange(
        index: 0,
        value: 4,
        lower: physicalRanges[0].lowerBound,
        upper: physicalRanges[0].upperBound
    )) {
        _ = try codec.normalizedActions(fromPhysicalTargets: [4, 0, 0, 0, 0])
    }
    #expect(throws: JointTargetActionCodec.CodecError.outOfNormalizedRange(
        index: 0,
        value: 2,
        lower: -1,
        upper: 1
    )) {
        _ = try codec.physicalTargets(fromNormalizedActions: [2, 0, 0, 0, 0])
    }

    let clampedTargets = try codec.physicalTargets(
        fromNormalizedActions: [2, -2, 0, 0, 0],
        decodingMode: .clamped
    )
    #expect(clampedTargets[0] == physicalRanges[0].upperBound)
    #expect(clampedTargets[1] == physicalRanges[1].lowerBound)
}

@Test func roArmM1ArmGripperBuilderRejectsMismatchedActionContractSchema() throws {
    let mismatchedContract = LearningProjectActionContract(
        schemaID: "not-roarm-m1-action-v1",
        kind: .continuous,
        driveCount: 5,
        actuatorCount: 5,
        isBounded: true,
        channels: LearningProjectActionContract.boundedChannels(
            names: RoArmM1ArmGripperSemantics.driveIDs,
            unit: "normalized",
            lowerBound: -1,
            upperBound: 1,
            transform: .tanh
        )
    )
    let builder = RoArmM1JointTargetTrainingDatasetBuilder(config: RoArmM1JointTargetTrainingDatasetBuilderConfig(
        actionContract: mismatchedContract
    ))
    #expect(throws: RoArmM1JointTargetTrainingDatasetBuilder.BuildError.actionContractSchemaMismatch(
        expected: RoArmM1JointTargetTrainingGoal.canonical.actionSchemaID,
        actual: mismatchedContract.schemaID
    )) {
        _ = try builder.build(from: makeRoArmM1JointTargetLog())
    }
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
    try makeRoArmM1JointTargetLog(events: [
        makeRoArmM1JointTargetStep(stepIndex: 0, positions: [0, 0, 0, 0, 0], targets: [0.02, 0.01, -0.01, 0.02, -0.02]),
        makeRoArmM1JointTargetStep(stepIndex: 1, positions: [0.03, 0.02, -0.02, 0.03, -0.03], targets: [0.04, 0.03, -0.03, 0.04, -0.04]),
    ])
}

private func makeRoArmM1JointTargetLog(events: [WorldStepLog]) throws -> SimulationLog {
    return try SimulationLog(
        scenarioId: ScenarioID("ROARM-M1-ARM-GRIPPER-TEST"),
        seed: ScenarioSeed(11),
        timeStep: TimeStep(delta: 0.02),
        determinism: DeterminismConfig(tier: .tier0, tier1Tolerance: nil),
        configHash: "roarm-m1-arm-gripper-test",
        events: events
    )
}

private func assertArrayApproximatelyEqual(
    _ lhs: [Double],
    _ rhs: [Double],
    tolerance: Double = 1e-9
) {
    #expect(lhs.count == rhs.count)
    for (left, right) in zip(lhs, rhs) {
        #expect(abs(left - right) <= tolerance)
    }
}

private func makeRoArmM1JointTargetStep(
    stepIndex: UInt64,
    positions: [Double],
    targets: [Double]
) throws -> WorldStepLog {
    try makeRoArmM1MixedDomainStep(
        stepIndex: stepIndex,
        jointPositions: positions,
        jointTargets: targets,
        actuatorPositions: positions,
        actuatorTargets: targets
    )
}

private func makeRoArmM1MixedDomainStep(
    stepIndex: UInt64,
    jointPositions: [Double],
    jointTargets: [Double],
    actuatorPositions: [Double],
    actuatorTargets: [Double]
) throws -> WorldStepLog {
    var scalars: [String: Double] = [:]
    for index in 0..<RoArmM1ServoCommandEncoder.jointCount {
        let actuatorSignalID = "joint_\(index + 1)"
        let jointScalarID = RoArmM1ArmGripperSemantics.jointScalarIDs[index]
        scalars[actuatorSignalID] = actuatorPositions[index]
        scalars["target_\(actuatorSignalID)"] = actuatorTargets[index]
        scalars["velocity_\(actuatorSignalID)"] = 0.01
        scalars["torque_\(actuatorSignalID)"] = 0.02
        scalars[jointScalarID] = jointPositions[index]
        scalars["target_\(jointScalarID)"] = jointTargets[index]
        scalars["velocity_\(jointScalarID)"] = 0.01
        scalars["torque_\(jointScalarID)"] = 0.02
    }

    return try WorldStepLog(
        time: WorldTime(stepIndex: stepIndex, time: Double(stepIndex) * 0.02),
        events: [.timeAdvance, .cutUpdate, .motorNerveUpdate, .plantIntegrate, .sensorSample],
        sensorSamples: [],
        driveIntents: jointTargets.enumerated().map { index, target in
            try DriveIntent(index: DriveIndex(UInt32(index)), activation: target, parameters: [])
        },
        reflexCorrections: [],
        actuatorValues: actuatorTargets.enumerated().map { index, target in
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
