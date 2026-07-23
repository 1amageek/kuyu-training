import Foundation
import KuyuTrainingValidation

public extension GeneratedTrainingArtifactCompatibilityVerifier {
    func compareProjectEvidencePacks(
        incumbentDirectory: URL,
        candidateDirectory: URL
    ) throws -> TrainingProjectEvidencePackComparison {
        let incumbent = try validatedProjectEvidencePack(in: incumbentDirectory)
        let candidate = try validatedProjectEvidencePack(in: candidateDirectory)
        return try compareProjectEvidencePacks(incumbent: incumbent, candidate: candidate)
    }

    func compareProjectEvidencePacks(
        incumbent: TrainingProjectEvidencePack,
        candidate: TrainingProjectEvidencePack
    ) throws -> TrainingProjectEvidencePackComparison {
        do {
            return try projectEvidenceComparator.compare(incumbent: incumbent, candidate: candidate)
        } catch let error as TrainingProjectEvidencePackValidator.ValidationError {
            throw VerificationError.invalidProjectEvidencePack(.invalidEvidencePack(error))
        }
    }

    func requirePreferredProjectEvidenceCandidate(
        _ comparison: TrainingProjectEvidencePackComparison
    ) throws {
        guard comparison.decision == .preferCandidate else {
            throw VerificationError.projectEvidenceCandidateNotPreferred(comparison)
        }
    }

    @discardableResult
    func requirePreferredProjectEvidenceCandidate(
        incumbentDirectory: URL,
        candidateDirectory: URL
    ) throws -> TrainingProjectEvidencePackComparison {
        let comparison = try compareProjectEvidencePacks(
            incumbentDirectory: incumbentDirectory,
            candidateDirectory: candidateDirectory
        )
        try requirePreferredProjectEvidenceCandidate(comparison)
        return comparison
    }

    func validateProjectEvidenceDatasetCuration(
        from artifactDirectory: URL,
        policy: TrainingDatasetCurationPolicy
    ) throws -> TrainingDatasetCurationReport {
        try validateProjectEvidenceDatasetCuration(
            validatedProjectEvidencePack(in: artifactDirectory),
            policy: policy
        )
    }

    func validateProjectEvidenceDatasetCuration(
        _ pack: TrainingProjectEvidencePack,
        policy: TrainingDatasetCurationPolicy
    ) throws -> TrainingDatasetCurationReport {
        do {
            return try datasetCurationValidator.validate(projectEvidencePack: pack, policy: policy)
        } catch let error as TrainingDatasetCurationPolicyValidator.ValidationError {
            throw VerificationError.projectEvidenceDatasetCurationRejected(error)
        }
    }
}
