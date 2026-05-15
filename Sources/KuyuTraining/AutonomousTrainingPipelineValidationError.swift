public enum AutonomousTrainingPipelineValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    case emptyPlanID
    case emptyStages
    case emptyStageID(index: Int)
    case duplicateStageID(String)
    case emptyStageTaskProfiles(String)
    case missingRequiredCapability(AutonomousCapability)
    case missingRequiredStage(AutonomousTrainingStageKind)
    case missingRequiredTerminalGate(AutonomousSafetyGateKind)
    case stageOrderViolation(requiredBefore: AutonomousTrainingStageKind, requiredAfter: AutonomousTrainingStageKind)
    case noBundleProducingStage

    public var description: String {
        switch self {
        case .emptyPlanID:
            return "empty-plan-id"
        case .emptyStages:
            return "empty-stages"
        case .emptyStageID(let index):
            return "empty-stage-id(index: \(index))"
        case .duplicateStageID(let stageID):
            return "duplicate-stage-id(\(stageID))"
        case .emptyStageTaskProfiles(let stageID):
            return "empty-stage-task-profiles(\(stageID))"
        case .missingRequiredCapability(let capability):
            return "missing-required-capability(\(capability.rawValue))"
        case .missingRequiredStage(let stage):
            return "missing-required-stage(\(stage.rawValue))"
        case .missingRequiredTerminalGate(let gate):
            return "missing-required-terminal-gate(\(gate.rawValue))"
        case .stageOrderViolation(let requiredBefore, let requiredAfter):
            return "stage-order-violation(\(requiredBefore.rawValue)-before-\(requiredAfter.rawValue))"
        case .noBundleProducingStage:
            return "no-bundle-producing-stage"
        }
    }
}
