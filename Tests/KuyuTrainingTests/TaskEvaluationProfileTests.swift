import KuyuTraining
import Testing

@Test func taskEvaluationProfileDefinesLiftContract() throws {
    let profile = try TaskEvaluationProfile.profile(task: "lift")

    #expect(profile.profileID == "lift-v1")
    #expect(profile.family == .referenceQuadrotor)
    #expect(profile.task == "lift")
    #expect(profile.observationChannelCount == 64)
    #expect(profile.baseEvaluationSuiteIDs == [1])
    #expect(profile.regressionSuiteIDs == [6, 7, 8])
    #expect(profile.minimumRewardAverage == 0)
    #expect(profile.minimumTaskPassRate == 1)
    #expect(profile.minimumHoldTimeRatio == 1)
    #expect(profile.maximumAltitudeErrorRatio == 1)
    #expect(profile.requiresParentCheckpointEvaluation)
    #expect(profile.liftThresholdSource == "scenario.liftEnvelope")
    #expect(profile.motorNerveSettings(controllerRawValue: "manasMLX").rateLimitPerSecond == 2)
    #expect(profile.motorNerveSettings(controllerRawValue: "Teacher Active Altitude Hold").rateLimitPerSecond == 100)
}

@Test func taskEvaluationProfileDefinesSingleLiftAsOneDriveLiftContract() throws {
    let profile = try TaskEvaluationProfile.profile(task: "singleLift")

    #expect(profile.profileID == "singleLift-v1")
    #expect(profile.family == .referenceQuadrotor)
    #expect(profile.task == "singleLift")
    #expect(profile.observationChannelCount == 8)
    #expect(profile.baseEvaluationSuiteIDs == [6])
    #expect(profile.minimumHoldTimeRatio == 1)
    #expect(profile.maximumAltitudeErrorRatio == 1)
    #expect(profile.requiresParentCheckpointEvaluation)
    #expect(profile.motorNerveSettings(controllerRawValue: "manasMLX").rateLimitPerSecond == 100)
}

@Test func taskEvaluationProfileDefinesAttitudeAsNonLiftContract() throws {
    let profile = try TaskEvaluationProfile.profile(task: "attitude")

    #expect(profile.profileID == "attitude-v1")
    #expect(profile.family == .referenceQuadrotor)
    #expect(profile.observationChannelCount == 16)
    #expect(profile.minimumRewardAverage == nil)
    #expect(profile.minimumHoldTimeRatio == nil)
    #expect(profile.maximumAltitudeErrorRatio == nil)
    #expect(!profile.requiresParentCheckpointEvaluation)

    var unstableHealth = RolloutHealth()
    unstableHealth.recordStabilityMetric(id: .maximumAttitudeDeviation, value: 2.0, aggregation: .maximum)
    unstableHealth.recordStabilityMetric(id: .maximumAngularRate, value: 2.0, aggregation: .maximum)
    unstableHealth.recordStabilityMetric(id: .minimumRootAltitude, value: 2.0, aggregation: .minimum)
    #expect(profile.stabilityLimitEnvelope.rejectionReasons(health: unstableHealth) == [.tiltRegressed])
}

@Test func taskEvaluationProfileDefinesRoArmM1AsProfileOwnedManipulatorContract() throws {
    let profile = try TaskEvaluationProfile.profile(task: RoArmM1JointTargetTrainingGoal.canonical.task)

    #expect(profile.family == .roArmM1ArmGripper)
    #expect(profile.family.expectedRobotClass == .manipulator)
    #expect(profile.profileID == RoArmM1JointTargetTrainingGoal.canonical.taskProfileID)
    #expect(profile.referenceEvaluatorID == "RoArmM1ArmGripperTargetTrackingEvaluator")
    #expect(profile.qualityEvaluatorID == "RoArmM1ArmGripperQualityEvaluator")
    #expect(profile.liftThresholdSource == nil)

    try TaskEvaluationProfileContractValidator().validate(profile, robotClass: .manipulator)
}

@Test func taskEvaluationProfileContractRejectsReferenceQuadrotorEvaluatorLeaks() throws {
    let profile = TaskEvaluationProfile(
        family: .roArmM1ArmGripper,
        profileID: "bad-roarm-profile",
        task: RoArmM1JointTargetTrainingGoal.canonical.task,
        observationChannelCount: 25,
        baseEvaluationSuiteIDs: [9],
        regressionSuiteIDs: [9],
        baselineMotorNerveSettings: TaskMotorNerveSettings(rateLimitPerSecond: 100, smoothingTimeConstant: nil),
        policyMotorNerveSettings: TaskMotorNerveSettings(rateLimitPerSecond: 2, smoothingTimeConstant: 0.08),
        minimumRewardAverage: 0,
        minimumTaskPassRate: 1,
        minimumHoldTimeRatio: nil,
        maximumAltitudeErrorRatio: nil,
        failOnTruncation: true,
        requiresReferenceTaskPass: true,
        requiresParentCheckpointEvaluation: false
    )

    #expect(throws: TaskEvaluationProfileContractValidationError.invalidProfile(
        profileID: "bad-roarm-profile",
        reason: "reference-quadrotor-reference-evaluator-leak"
    )) {
        try TaskEvaluationProfileContractValidator().validate(profile, robotClass: .manipulator)
    }
}

@Test func taskEvaluationProfileContractRejectsRobotClassMismatch() throws {
    let profile = try TaskEvaluationProfile.profile(task: RoArmM1JointTargetTrainingGoal.canonical.task)

    #expect(throws: TaskEvaluationProfileContractValidationError.invalidProfile(
        profileID: RoArmM1JointTargetTrainingGoal.canonical.taskProfileID,
        reason: "robot-class-mismatch"
    )) {
        try TaskEvaluationProfileContractValidator().validate(profile, robotClass: .aerialVehicle)
    }
}

@Test func taskEvaluationProfileRejectsUnsupportedTasks() {
    do {
        _ = try TaskEvaluationProfile.profile(task: "hover")
        Issue.record("Expected unsupported task to throw.")
    } catch TaskEvaluationProfileError.unsupportedTask(let task) {
        #expect(task == "hover")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
