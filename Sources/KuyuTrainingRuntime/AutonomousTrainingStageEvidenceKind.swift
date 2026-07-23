import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation
public enum AutonomousTrainingStageEvidenceKind: String, Codable, Sendable, Equatable, CaseIterable {
    case trainingRunArtifact
    case checkpointEvaluation
    case regressionSummary
    case reinforcementStageArtifact
    case evolutionArtifact
    case worldModelArtifact
    case projectEvidencePack
    case modelBundle
    case campaignSummary
    case external
}
