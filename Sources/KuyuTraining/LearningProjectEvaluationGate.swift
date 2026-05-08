import Foundation

public struct LearningProjectEvaluationGate: Codable, Sendable, Equatable {
    public let minimumRewardAverage: Double?
    public let minimumTaskPassRate: Double
    public let minimumHoldTimeRatio: Double?
    public let maximumAltitudeErrorRatio: Double?
    public let failOnTruncation: Bool
    public let requiredSafetyGates: [AutonomousSafetyGateKind]

    public init(
        minimumRewardAverage: Double?,
        minimumTaskPassRate: Double,
        minimumHoldTimeRatio: Double?,
        maximumAltitudeErrorRatio: Double?,
        failOnTruncation: Bool,
        requiredSafetyGates: [AutonomousSafetyGateKind]
    ) {
        self.minimumRewardAverage = minimumRewardAverage
        self.minimumTaskPassRate = minimumTaskPassRate
        self.minimumHoldTimeRatio = minimumHoldTimeRatio
        self.maximumAltitudeErrorRatio = maximumAltitudeErrorRatio
        self.failOnTruncation = failOnTruncation
        self.requiredSafetyGates = requiredSafetyGates
    }

    public static func from(profile: TaskEvaluationProfile) -> LearningProjectEvaluationGate {
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
