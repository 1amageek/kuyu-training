import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation
public enum AutonomousTrainingStageEvidenceKind: String, Codable, Sendable, Equatable, CaseIterable {
    case trainingRunArtifact
    case checkpointEvaluation
    case regressionSummary
    case evolutionArtifact
    case modelBundle
    case campaignSummary
    case external
}
