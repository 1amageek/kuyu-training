import KuyuTrainingContracts

public enum TaskEvaluationProfileFamily: String, Sendable, Codable, Equatable, CaseIterable {
    case referenceQuadrotor
    case roArmM1ArmGripper

    public var expectedRobotClass: LearningProjectRobotClass {
        switch self {
        case .referenceQuadrotor:
            return .aerialVehicle
        case .roArmM1ArmGripper:
            return .manipulator
        }
    }

    public var allowsReferenceQuadrotorEvaluators: Bool {
        self == .referenceQuadrotor
    }
}
