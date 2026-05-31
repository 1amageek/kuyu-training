import Foundation

public enum RoArmM1JointTargetTrainingStatus: String, Codable, Sendable, Equatable {
    case achieved
    case notAchieved
}

public struct RoArmM1JointTargetPerJointMetrics: Codable, Sendable, Equatable {
    public let jointID: String
    public let meanAbsoluteErrorRadians: Double
    public let maximumAbsoluteErrorRadians: Double
    public let maximumAbsoluteVelocityRadiansPerSecond: Double
    public let jointLimitViolationCount: Int

    public init(
        jointID: String,
        meanAbsoluteErrorRadians: Double,
        maximumAbsoluteErrorRadians: Double,
        maximumAbsoluteVelocityRadiansPerSecond: Double,
        jointLimitViolationCount: Int
    ) {
        self.jointID = jointID
        self.meanAbsoluteErrorRadians = meanAbsoluteErrorRadians
        self.maximumAbsoluteErrorRadians = maximumAbsoluteErrorRadians
        self.maximumAbsoluteVelocityRadiansPerSecond = maximumAbsoluteVelocityRadiansPerSecond
        self.jointLimitViolationCount = jointLimitViolationCount
    }
}

public struct RoArmM1JointTargetTrainingReport: Codable, Sendable, Equatable {
    public let goal: RoArmM1JointTargetTrainingGoal
    public let status: RoArmM1JointTargetTrainingStatus
    public let scenarioID: String
    public let seed: UInt64
    public let durationSeconds: Double
    public let timeStepSeconds: Double
    public let recordCount: Int
    public let sourceRecordCount: Int
    public let hindsightRecordCount: Int
    public let rewardSum: Double
    public let meanAbsoluteErrorRadians: Double
    public let maximumAbsoluteErrorRadians: Double
    public let maximumAbsoluteVelocityRadiansPerSecond: Double
    public let movementMagnitudeRadians: Double
    public let jointLimitViolationCount: Int
    public let nonFiniteRecordCount: Int
    public let perJoint: [RoArmM1JointTargetPerJointMetrics]
    public let activeEfficiencyTechniqueIDs: [String]

    public var passed: Bool {
        status == .achieved
    }

    public init(
        goal: RoArmM1JointTargetTrainingGoal,
        status: RoArmM1JointTargetTrainingStatus,
        scenarioID: String,
        seed: UInt64,
        durationSeconds: Double,
        timeStepSeconds: Double,
        recordCount: Int,
        sourceRecordCount: Int,
        hindsightRecordCount: Int,
        rewardSum: Double,
        meanAbsoluteErrorRadians: Double,
        maximumAbsoluteErrorRadians: Double,
        maximumAbsoluteVelocityRadiansPerSecond: Double,
        movementMagnitudeRadians: Double,
        jointLimitViolationCount: Int,
        nonFiniteRecordCount: Int,
        perJoint: [RoArmM1JointTargetPerJointMetrics],
        activeEfficiencyTechniqueIDs: [String]
    ) {
        self.goal = goal
        self.status = status
        self.scenarioID = scenarioID
        self.seed = seed
        self.durationSeconds = durationSeconds
        self.timeStepSeconds = timeStepSeconds
        self.recordCount = recordCount
        self.sourceRecordCount = sourceRecordCount
        self.hindsightRecordCount = hindsightRecordCount
        self.rewardSum = rewardSum
        self.meanAbsoluteErrorRadians = meanAbsoluteErrorRadians
        self.maximumAbsoluteErrorRadians = maximumAbsoluteErrorRadians
        self.maximumAbsoluteVelocityRadiansPerSecond = maximumAbsoluteVelocityRadiansPerSecond
        self.movementMagnitudeRadians = movementMagnitudeRadians
        self.jointLimitViolationCount = jointLimitViolationCount
        self.nonFiniteRecordCount = nonFiniteRecordCount
        self.perJoint = perJoint
        self.activeEfficiencyTechniqueIDs = activeEfficiencyTechniqueIDs
    }
}
