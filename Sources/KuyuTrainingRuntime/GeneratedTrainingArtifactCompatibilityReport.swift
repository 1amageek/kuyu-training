import KuyuEvolution
import KuyuTrainingValidation

public struct GeneratedTrainingArtifactCompatibilityReport: Sendable, Equatable {
    public let runArtifacts: TrainingRunArtifactBundle?
    public let probeArtifacts: TrainingProbeArtifactBundle?
    public let evolutionArtifacts: EvolutionRunArtifactBundle?
    public let checkpointEvaluationArtifact: CheckpointEvaluationArtifact?
    public let projectEvidencePack: TrainingProjectEvidencePack?
    public let observabilityArtifact: ConsciousUnconsciousObservabilityArtifact?
    public let summaryOutcomeArtifact: TrainingRunSummaryOutcomeArtifact?

    public init(
        runArtifacts: TrainingRunArtifactBundle? = nil,
        probeArtifacts: TrainingProbeArtifactBundle? = nil,
        evolutionArtifacts: EvolutionRunArtifactBundle? = nil,
        checkpointEvaluationArtifact: CheckpointEvaluationArtifact? = nil,
        projectEvidencePack: TrainingProjectEvidencePack? = nil,
        observabilityArtifact: ConsciousUnconsciousObservabilityArtifact? = nil,
        summaryOutcomeArtifact: TrainingRunSummaryOutcomeArtifact? = nil
    ) {
        self.runArtifacts = runArtifacts
        self.probeArtifacts = probeArtifacts
        self.evolutionArtifacts = evolutionArtifacts
        self.checkpointEvaluationArtifact = checkpointEvaluationArtifact
        self.projectEvidencePack = projectEvidencePack
        self.observabilityArtifact = observabilityArtifact
        self.summaryOutcomeArtifact = summaryOutcomeArtifact
    }
}
