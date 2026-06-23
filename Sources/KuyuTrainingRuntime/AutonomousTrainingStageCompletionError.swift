import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation
public enum AutonomousTrainingStageCompletionError: Error, Sendable, Equatable, CustomStringConvertible {
    case stageKindUnsupported(AutonomousTrainingStageKind)
    case trainingRunModeMismatch(expected: [LearningRunMode], actual: LearningRunMode)
    case trainingRunProfileMismatch(expected: [String], actual: String)
    case trainingRunNotAccepted(reason: String)
    case checkpointDecisionNotAccepted(CheckpointDecisionState)
    case missingCheckpointEvidence

    public var description: String {
        switch self {
        case .stageKindUnsupported(let kind):
            return "stageKindUnsupported(\(kind.rawValue))"
        case .trainingRunModeMismatch(let expected, let actual):
            return "trainingRunModeMismatch(expected: \(expected.map(\.rawValue)), actual: \(actual.rawValue))"
        case .trainingRunProfileMismatch(let expected, let actual):
            return "trainingRunProfileMismatch(expected: \(expected), actual: \(actual))"
        case .trainingRunNotAccepted(let reason):
            return "trainingRunNotAccepted(\(reason))"
        case .checkpointDecisionNotAccepted(let state):
            return "checkpointDecisionNotAccepted(\(state.rawValue))"
        case .missingCheckpointEvidence:
            return "missingCheckpointEvidence"
        }
    }
}
