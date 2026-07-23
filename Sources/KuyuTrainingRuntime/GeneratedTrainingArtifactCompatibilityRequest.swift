import Foundation

public struct GeneratedTrainingArtifactCompatibilityRequest: Sendable, Equatable {
    public let runArtifactDirectory: URL?
    public let probeArtifactDirectory: URL?
    public let evolutionArtifactDirectory: URL?
    public let checkpointEvaluation: CheckpointEvaluationArtifactCompatibilityRequest?
    public let projectEvidencePackDirectory: URL?
    public let observabilityArtifactURL: URL?
    public let summaryOutcomeDirectory: URL?

    public init(
        runArtifactDirectory: URL? = nil,
        probeArtifactDirectory: URL? = nil,
        evolutionArtifactDirectory: URL? = nil,
        checkpointEvaluation: CheckpointEvaluationArtifactCompatibilityRequest? = nil,
        projectEvidencePackDirectory: URL? = nil,
        observabilityArtifactURL: URL? = nil,
        summaryOutcomeDirectory: URL? = nil
    ) {
        self.runArtifactDirectory = runArtifactDirectory
        self.probeArtifactDirectory = probeArtifactDirectory
        self.evolutionArtifactDirectory = evolutionArtifactDirectory
        self.checkpointEvaluation = checkpointEvaluation
        self.projectEvidencePackDirectory = projectEvidencePackDirectory
        self.observabilityArtifactURL = observabilityArtifactURL
        self.summaryOutcomeDirectory = summaryOutcomeDirectory
    }
}
