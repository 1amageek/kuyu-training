import KuyuTraining
import Testing

@Test func taskEvaluationProfileDefinesLiftContract() throws {
    let profile = try TaskEvaluationProfile.profile(task: "lift")

    #expect(profile.profileID == "lift-v1")
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
    #expect(profile.observationChannelCount == 16)
    #expect(profile.minimumRewardAverage == nil)
    #expect(profile.minimumHoldTimeRatio == nil)
    #expect(profile.maximumAltitudeErrorRatio == nil)
    #expect(!profile.requiresParentCheckpointEvaluation)
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
