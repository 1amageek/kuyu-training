import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public extension LearningProjectEvaluationGate {
    static func from(profile: TaskEvaluationProfile) -> LearningProjectEvaluationGate {
        LearningProjectEvaluationGate(
            minimumRewardAverage: profile.minimumRewardAverage,
            minimumTaskPassRate: profile.minimumTaskPassRate,
            minimumHoldTimeRatio: profile.minimumHoldTimeRatio,
            maximumAltitudeErrorRatio: profile.maximumAltitudeErrorRatio,
            failOnTruncation: profile.failOnTruncation,
            requiredSafetyGates: [
                .modelBundleValidated,
                .deterministicReplayValidated,
                .scenarioRegressionPassed,
                .telemetryComplete,
                .artifactLineageComplete
            ]
        )
    }
}
