import Foundation
import KuyuTrainingContracts

public enum TaskEvaluationProfileContractValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidProfile(profileID: String, reason: String)

    public var description: String {
        switch self {
        case let .invalidProfile(profileID, reason):
            return "invalid-task-profile-contract profile=\(profileID) reason=\(reason)"
        }
    }
}

public struct TaskEvaluationProfileContractValidator: Sendable {
    public init() {}

    public func validate(
        _ profile: TaskEvaluationProfile,
        robotClass: LearningProjectRobotClass? = nil
    ) throws {
        try require(!profile.profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, profile, "empty-profile-id")
        try require(!profile.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, profile, "empty-task")
        try require(profile.observationChannelCount > 0, profile, "non-positive-observation-channel-count")
        try require(!profile.baseEvaluationSuiteIDs.isEmpty, profile, "empty-base-evaluation-suites")
        try require(!profile.regressionSuiteIDs.isEmpty, profile, "empty-regression-suites")
        try require(profile.baseEvaluationSuiteIDs.allSatisfy { $0 >= 0 }, profile, "negative-base-evaluation-suite")
        try require(profile.regressionSuiteIDs.allSatisfy { $0 >= 0 }, profile, "negative-regression-suite")
        try validate(
            profile.baselineMotorNerveSettings,
            field: "baseline-motor-nerve",
            profile: profile
        )
        try validate(
            profile.policyMotorNerveSettings,
            field: "policy-motor-nerve",
            profile: profile
        )
        if let minimumRewardAverage = profile.minimumRewardAverage {
            try require(minimumRewardAverage.isFinite, profile, "non-finite-minimum-reward")
        }
        try require(
            profile.minimumTaskPassRate.isFinite
                && profile.minimumTaskPassRate >= 0
                && profile.minimumTaskPassRate <= 1,
            profile,
            "invalid-minimum-task-pass-rate"
        )
        if let minimumHoldTimeRatio = profile.minimumHoldTimeRatio {
            try require(
                minimumHoldTimeRatio.isFinite && minimumHoldTimeRatio >= 0,
                profile,
                "invalid-minimum-hold-time-ratio"
            )
        }
        if let maximumAltitudeErrorRatio = profile.maximumAltitudeErrorRatio {
            try require(
                maximumAltitudeErrorRatio.isFinite && maximumAltitudeErrorRatio >= 0,
                profile,
                "invalid-maximum-altitude-error-ratio"
            )
        }
        try require(
            !profile.referenceEvaluatorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            profile,
            "empty-reference-evaluator-id"
        )
        try require(
            !profile.qualityEvaluatorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            profile,
            "empty-quality-evaluator-id"
        )
        if let robotClass {
            try require(
                profile.family.expectedRobotClass == robotClass,
                profile,
                "robot-class-mismatch"
            )
        }
        if !profile.family.allowsReferenceQuadrotorEvaluators {
            try require(
                !profile.referenceEvaluatorID.hasPrefix("ReferenceQuadrotor"),
                profile,
                "reference-quadrotor-reference-evaluator-leak"
            )
            try require(
                !profile.qualityEvaluatorID.hasPrefix("ReferenceQuadrotor"),
                profile,
                "reference-quadrotor-quality-evaluator-leak"
            )
            try require(
                profile.liftThresholdSource != "scenario.liftEnvelope",
                profile,
                "reference-quadrotor-lift-threshold-leak"
            )
        }
    }

    private func validate(
        _ settings: TaskMotorNerveSettings,
        field: String,
        profile: TaskEvaluationProfile
    ) throws {
        try require(
            settings.rateLimitPerSecond.isFinite && settings.rateLimitPerSecond > 0,
            profile,
            "\(field)-invalid-rate-limit"
        )
        if let smoothingTimeConstant = settings.smoothingTimeConstant {
            try require(
                smoothingTimeConstant.isFinite && smoothingTimeConstant > 0,
                profile,
                "\(field)-invalid-smoothing-time-constant"
            )
        }
    }

    private func require(
        _ condition: Bool,
        _ profile: TaskEvaluationProfile,
        _ reason: String
    ) throws {
        guard condition else {
            throw TaskEvaluationProfileContractValidationError.invalidProfile(
                profileID: profile.profileID,
                reason: reason
            )
        }
    }
}
