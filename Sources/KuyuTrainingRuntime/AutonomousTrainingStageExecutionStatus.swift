import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation
public enum AutonomousTrainingStageExecutionStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case pending
    case completed
    case blocked
    case skipped
}
