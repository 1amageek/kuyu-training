import Foundation
import KuyuScenarios

public enum TaskEvaluationProfileError: Error, Sendable, Equatable {
    case unsupportedTask(String)
}

public struct TaskMotorNerveSettings: Sendable, Codable, Equatable {
    public let rateLimitPerSecond: Double
    public let smoothingTimeConstant: Double?

    public init(rateLimitPerSecond: Double, smoothingTimeConstant: Double?) {
        self.rateLimitPerSecond = rateLimitPerSecond
        self.smoothingTimeConstant = smoothingTimeConstant
    }
}

public struct TaskEvaluationProfile: Sendable, Codable, Equatable {
    public let profileID: String
    public let task: String
    public let observationChannelCount: Int
    public let baseEvaluationSuiteIDs: [Int]
    public let regressionSuiteIDs: [Int]
    public let baselineMotorNerveSettings: TaskMotorNerveSettings
    public let policyMotorNerveSettings: TaskMotorNerveSettings
    public let minimumRewardAverage: Double?
    public let minimumTaskPassRate: Double
    public let minimumHoldTimeRatio: Double?
    public let maximumAltitudeErrorRatio: Double?
    public let failOnTruncation: Bool
    public let requiresReferenceTaskPass: Bool
    public let requiresParentCheckpointEvaluation: Bool
    public let referenceEvaluatorID: String
    public let qualityEvaluatorID: String
    public let liftThresholdSource: String?
    public let stabilityLimitEnvelope: RolloutStabilityLimitEnvelope

    public init(
        profileID: String,
        task: String,
        observationChannelCount: Int,
        baseEvaluationSuiteIDs: [Int],
        regressionSuiteIDs: [Int],
        baselineMotorNerveSettings: TaskMotorNerveSettings,
        policyMotorNerveSettings: TaskMotorNerveSettings,
        minimumRewardAverage: Double?,
        minimumTaskPassRate: Double,
        minimumHoldTimeRatio: Double?,
        maximumAltitudeErrorRatio: Double?,
        failOnTruncation: Bool,
        requiresReferenceTaskPass: Bool,
        requiresParentCheckpointEvaluation: Bool,
        referenceEvaluatorID: String = "ReferenceQuadrotorScenarioEvaluator",
        qualityEvaluatorID: String = "ReferenceQuadrotorTaskQualityEvaluator",
        liftThresholdSource: String? = nil,
        stabilityLimitEnvelope: RolloutStabilityLimitEnvelope = .unbounded
    ) {
        self.profileID = profileID
        self.task = task
        self.observationChannelCount = observationChannelCount
        self.baseEvaluationSuiteIDs = baseEvaluationSuiteIDs
        self.regressionSuiteIDs = regressionSuiteIDs
        self.baselineMotorNerveSettings = baselineMotorNerveSettings
        self.policyMotorNerveSettings = policyMotorNerveSettings
        self.minimumRewardAverage = minimumRewardAverage
        self.minimumTaskPassRate = minimumTaskPassRate
        self.minimumHoldTimeRatio = minimumHoldTimeRatio
        self.maximumAltitudeErrorRatio = maximumAltitudeErrorRatio
        self.failOnTruncation = failOnTruncation
        self.requiresReferenceTaskPass = requiresReferenceTaskPass
        self.requiresParentCheckpointEvaluation = requiresParentCheckpointEvaluation
        self.referenceEvaluatorID = referenceEvaluatorID
        self.qualityEvaluatorID = qualityEvaluatorID
        self.liftThresholdSource = liftThresholdSource
        self.stabilityLimitEnvelope = stabilityLimitEnvelope
    }

    public static func profile(task: String) throws -> TaskEvaluationProfile {
        switch task {
        case "attitude":
            return TaskEvaluationProfile(
                profileID: "attitude-v1",
                task: "attitude",
                // 16-channel privileged body-rate observation (euler angles +
                // angular velocity + velocity + target delta + previous action),
                // built by ReferenceQuadrotorBodyRateObservationEncoder. This is the
                // task-appropriate attitude observation and is consistent with the
                // lift actor (also a privileged encoded observation); raw IMU (6) was
                // not zero-padded "starvation" but simply a weaker signal.
                observationChannelCount: 16,
                baseEvaluationSuiteIDs: [1],
                regressionSuiteIDs: [6, 7, 8],
                baselineMotorNerveSettings: TaskMotorNerveSettings(rateLimitPerSecond: 100, smoothingTimeConstant: nil),
                policyMotorNerveSettings: TaskMotorNerveSettings(rateLimitPerSecond: 2, smoothingTimeConstant: 0.08),
                minimumRewardAverage: nil,
                minimumTaskPassRate: 1,
                minimumHoldTimeRatio: nil,
                maximumAltitudeErrorRatio: nil,
                failOnTruncation: false,
                requiresReferenceTaskPass: true,
                requiresParentCheckpointEvaluation: false,
                stabilityLimitEnvelope: try referenceQuadrotorAttitudeStabilityLimits()
            )
        case "lift":
            return liftProfile(task: "lift", profileID: "lift-v1")
        case "singleLift":
            return liftProfile(
                task: "singleLift",
                profileID: "singleLift-v1",
                observationChannelCount: 8,
                baseEvaluationSuiteIDs: [6],
                policyMotorNerveSettings: TaskMotorNerveSettings(rateLimitPerSecond: 100, smoothingTimeConstant: nil)
            )
        case RoArmM1JointTargetTrainingGoal.canonical.task:
            return TaskEvaluationProfile(
                profileID: RoArmM1JointTargetTrainingGoal.canonical.taskProfileID,
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
                requiresParentCheckpointEvaluation: false,
                referenceEvaluatorID: "RoArmM1ArmGripperTargetTrackingEvaluator",
                qualityEvaluatorID: "RoArmM1ArmGripperQualityEvaluator",
                liftThresholdSource: nil
            )
        default:
            throw TaskEvaluationProfileError.unsupportedTask(task)
        }
    }

    public static func profile(profileID: String) throws -> TaskEvaluationProfile {
        switch profileID {
        case "attitude", "attitude-v1":
            return try profile(task: "attitude")
        case "lift", "lift-v1":
            return try profile(task: "lift")
        case "singleLift", "singleLift-v1":
            return try profile(task: "singleLift")
        case "roArmM1ArmGripperTargetTracking", "roArmM1ArmGripperTargetTracking-v1":
            return try profile(task: RoArmM1JointTargetTrainingGoal.canonical.task)
        default:
            throw TaskEvaluationProfileError.unsupportedTask(profileID)
        }
    }

    public static func profile(taskMode: SimulationTaskMode) throws -> TaskEvaluationProfile {
        switch taskMode {
        case .attitude:
            return try profile(task: "attitude")
        case .lift:
            return try profile(task: "lift")
        case .singleLift:
            return try profile(task: "singleLift")
        }
    }

    public func motorNerveSettings(controllerRawValue: String) -> TaskMotorNerveSettings {
        switch controllerRawValue {
        case "Teacher Active Altitude Hold", "Sensor Baseline":
            return baselineMotorNerveSettings
        default:
            return policyMotorNerveSettings
        }
    }

    private static func liftProfile(
        task: String,
        profileID: String,
        observationChannelCount: Int = 64,
        baseEvaluationSuiteIDs: [Int] = [1],
        policyMotorNerveSettings: TaskMotorNerveSettings = TaskMotorNerveSettings(
            rateLimitPerSecond: 2,
            smoothingTimeConstant: 0.08
        )
    ) -> TaskEvaluationProfile {
        TaskEvaluationProfile(
            profileID: profileID,
            task: task,
            observationChannelCount: observationChannelCount,
            baseEvaluationSuiteIDs: baseEvaluationSuiteIDs,
            regressionSuiteIDs: [6, 7, 8],
            baselineMotorNerveSettings: TaskMotorNerveSettings(rateLimitPerSecond: 100, smoothingTimeConstant: nil),
            policyMotorNerveSettings: policyMotorNerveSettings,
            minimumRewardAverage: 0,
            minimumTaskPassRate: 1,
            minimumHoldTimeRatio: 1,
            maximumAltitudeErrorRatio: 1,
            failOnTruncation: false,
            requiresReferenceTaskPass: true,
            requiresParentCheckpointEvaluation: true,
            liftThresholdSource: "scenario.liftEnvelope"
        )
    }

    public static func referenceQuadrotorAttitudeStabilityLimits() throws -> RolloutStabilityLimitEnvelope {
        try RolloutStabilityLimitEnvelope.rootRigidBody(
            maximumAngularRate: 8.0,
            maximumAttitudeDeviation: 1.25,
            minimumRootAltitude: 1.75
        )
    }
}
