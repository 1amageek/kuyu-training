import Foundation

public enum RoArmM1JointTargetTrainingStatus: String, Codable, Sendable, Equatable {
    case achieved
    case notAchieved
}

public struct RoArmM1ArmGripperDriveMetrics: Codable, Sendable, Equatable {
    public let driveID: String
    public let meanAbsoluteErrorRadians: Double
    public let maximumAbsoluteErrorRadians: Double
    public let maximumAbsoluteVelocityRadiansPerSecond: Double
    public let limitViolationCount: Int

    public init(
        driveID: String,
        meanAbsoluteErrorRadians: Double,
        maximumAbsoluteErrorRadians: Double,
        maximumAbsoluteVelocityRadiansPerSecond: Double,
        limitViolationCount: Int
    ) {
        self.driveID = driveID
        self.meanAbsoluteErrorRadians = meanAbsoluteErrorRadians
        self.maximumAbsoluteErrorRadians = maximumAbsoluteErrorRadians
        self.maximumAbsoluteVelocityRadiansPerSecond = maximumAbsoluteVelocityRadiansPerSecond
        self.limitViolationCount = limitViolationCount
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
    public let perDrive: [RoArmM1ArmGripperDriveMetrics]
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
        perDrive: [RoArmM1ArmGripperDriveMetrics],
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
        self.perDrive = perDrive
        self.activeEfficiencyTechniqueIDs = activeEfficiencyTechniqueIDs
    }
}
