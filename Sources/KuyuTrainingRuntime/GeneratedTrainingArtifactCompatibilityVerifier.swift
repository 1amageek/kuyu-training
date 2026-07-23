import KuyuEvolution
import KuyuTrainingValidation

public struct GeneratedTrainingArtifactCompatibilityVerifier: Sendable {
    public enum VerificationError: Error, Sendable, Equatable {
        case emptyRequest
        case missingEvolutionArtifact(String)
        case invalidEvolutionArtifact(String)
        case evolutionCheckpointNotAccepted([String])
        case missingCheckpointEvaluationArtifact(String)
        case invalidCheckpointEvaluationArtifact(CheckpointEvaluationArtifactCompatibilityFailure)
        case invalidProjectEvidencePack(TrainingProjectEvidencePackArtifactStore.StoreError)
        case invalidObservabilityArtifact(ConsciousUnconsciousObservabilityArtifactStore.StoreError)
        case invalidSummaryOutcomeArtifact(TrainingRunSummaryOutcomeArtifactStore.StoreError)
        case projectEvidenceCandidateNotPreferred(TrainingProjectEvidencePackComparison)
        case projectEvidenceDatasetCurationRejected(TrainingDatasetCurationPolicyValidator.ValidationError)
        case incompatibleRunAndProbeArtifacts(runID: String, probeTrainingRunID: String)
    }

    let runValidator: TrainingRunArtifactValidator
    let probeValidator: TrainingProbeArtifactValidator
    let evolutionValidator: EvolutionRunArtifactValidator
    let projectEvidenceStore: TrainingProjectEvidencePackArtifactStore
    let observabilityArtifactStore: ConsciousUnconsciousObservabilityArtifactStore
    let summaryOutcomeStore: TrainingRunSummaryOutcomeArtifactStore
    let projectEvidenceComparator: TrainingProjectEvidencePackComparator
    let datasetCurationValidator: TrainingDatasetCurationPolicyValidator

    public init(
        runValidator: TrainingRunArtifactValidator = TrainingRunArtifactValidator(),
        probeValidator: TrainingProbeArtifactValidator = TrainingProbeArtifactValidator(),
        evolutionValidator: EvolutionRunArtifactValidator = EvolutionRunArtifactValidator(),
        projectEvidenceStore: TrainingProjectEvidencePackArtifactStore = TrainingProjectEvidencePackArtifactStore(),
        observabilityArtifactStore: ConsciousUnconsciousObservabilityArtifactStore =
            ConsciousUnconsciousObservabilityArtifactStore(),
        summaryOutcomeStore: TrainingRunSummaryOutcomeArtifactStore =
            TrainingRunSummaryOutcomeArtifactStore(),
        projectEvidenceComparator: TrainingProjectEvidencePackComparator = TrainingProjectEvidencePackComparator(),
        datasetCurationValidator: TrainingDatasetCurationPolicyValidator =
            TrainingDatasetCurationPolicyValidator()
    ) {
        self.runValidator = runValidator
        self.probeValidator = probeValidator
        self.evolutionValidator = evolutionValidator
        self.projectEvidenceStore = projectEvidenceStore
        self.observabilityArtifactStore = observabilityArtifactStore
        self.summaryOutcomeStore = summaryOutcomeStore
        self.projectEvidenceComparator = projectEvidenceComparator
        self.datasetCurationValidator = datasetCurationValidator
    }
}
