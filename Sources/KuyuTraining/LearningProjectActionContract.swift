import Foundation

public enum LearningProjectActionSpaceKind: String, Codable, Sendable, Equatable, CaseIterable {
    case continuous
    case discrete
    case hybrid
}

public struct LearningProjectActionContract: Codable, Sendable, Equatable {
    public let schemaID: String
    public let kind: LearningProjectActionSpaceKind
    public let driveCount: Int?
    public let actuatorCount: Int?
    public let isBounded: Bool

    public init(
        schemaID: String,
        kind: LearningProjectActionSpaceKind,
        driveCount: Int?,
        actuatorCount: Int?,
        isBounded: Bool
    ) {
        self.schemaID = schemaID
        self.kind = kind
        self.driveCount = driveCount
        self.actuatorCount = actuatorCount
        self.isBounded = isBounded
    }

    public static func referenceQuadrotorBodyRateControl() -> LearningProjectActionContract {
        LearningProjectActionContract(
            schemaID: "reference-quadrotor-body-rate-control-action-v1",
            kind: .continuous,
            driveCount: 4,
            actuatorCount: 4,
            isBounded: true
        )
    }

    public static func roArmM1JointTargets() -> LearningProjectActionContract {
        LearningProjectActionContract(
            schemaID: RoArmM1JointTargetTrainingGoal.canonical.actionSchemaID,
            kind: .continuous,
            driveCount: 5,
            actuatorCount: 5,
            isBounded: true
        )
    }
}
