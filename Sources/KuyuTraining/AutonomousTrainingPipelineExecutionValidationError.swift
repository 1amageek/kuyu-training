public enum AutonomousTrainingPipelineExecutionValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    case schemaVersionMismatch(expected: Int, actual: Int)
    case planIDMismatch(expected: String, actual: String)
    case domainMismatch(expected: AutonomousOperationDomain, actual: AutonomousOperationDomain)
    case stageCountMismatch(expected: Int, actual: Int)
    case missingStageRecord(String)
    case unexpectedStageRecord(String)
    case duplicateStageRecord(String)
    case stageKindMismatch(stageID: String, expected: AutonomousTrainingStageKind, actual: AutonomousTrainingStageKind)
    case completedStageMissingExitGate(stageID: String, gate: AutonomousSafetyGateKind)
    case completedStageMissingEvidence(stageID: String)
    case completedStageMissingGateEvidence(stageID: String, gate: AutonomousSafetyGateKind)
    case invalidEvidencePath(stageID: String)
    case unexpectedTerminalGate(AutonomousSafetyGateKind)

    public var description: String {
        switch self {
        case .schemaVersionMismatch(let expected, let actual):
            return "schemaVersionMismatch(expected: \(expected), actual: \(actual))"
        case .planIDMismatch(let expected, let actual):
            return "planIDMismatch(expected: \(expected), actual: \(actual))"
        case .domainMismatch(let expected, let actual):
            return "domainMismatch(expected: \(expected.rawValue), actual: \(actual.rawValue))"
        case .stageCountMismatch(let expected, let actual):
            return "stageCountMismatch(expected: \(expected), actual: \(actual))"
        case .missingStageRecord(let stageID):
            return "missingStageRecord(\(stageID))"
        case .unexpectedStageRecord(let stageID):
            return "unexpectedStageRecord(\(stageID))"
        case .duplicateStageRecord(let stageID):
            return "duplicateStageRecord(\(stageID))"
        case .stageKindMismatch(let stageID, let expected, let actual):
            return "stageKindMismatch(stageID: \(stageID), expected: \(expected.rawValue), actual: \(actual.rawValue))"
        case .completedStageMissingExitGate(let stageID, let gate):
            return "completedStageMissingExitGate(stageID: \(stageID), gate: \(gate.rawValue))"
        case .completedStageMissingEvidence(let stageID):
            return "completedStageMissingEvidence(\(stageID))"
        case .completedStageMissingGateEvidence(let stageID, let gate):
            return "completedStageMissingGateEvidence(stageID: \(stageID), gate: \(gate.rawValue))"
        case .invalidEvidencePath(let stageID):
            return "invalidEvidencePath(\(stageID))"
        case .unexpectedTerminalGate(let gate):
            return "unexpectedTerminalGate(\(gate.rawValue))"
        }
    }
}
