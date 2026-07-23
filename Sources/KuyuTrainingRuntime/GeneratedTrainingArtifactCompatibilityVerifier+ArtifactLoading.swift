import Foundation
import KuyuEvolution
import KuyuTrainingValidation

public extension GeneratedTrainingArtifactCompatibilityVerifier {
    func validatedRunArtifacts(in artifactDirectory: URL) throws -> TrainingRunArtifactBundle {
        try runValidator.validatedBundle(in: artifactDirectory)
    }

    func validatedProbeArtifacts(in artifactDirectory: URL) throws -> TrainingProbeArtifactBundle {
        try probeValidator.validatedBundle(in: artifactDirectory)
    }

    func validatedProbeAcceptance(in artifactDirectory: URL) throws -> TrainingProbeAcceptanceReceipt {
        try probeValidator.validatedAcceptance(in: artifactDirectory)
    }

    func validatedEvolutionArtifacts(in artifactDirectory: URL) throws -> EvolutionRunArtifactBundle {
        do {
            return try evolutionValidator.validatedBundle(in: artifactDirectory)
        } catch EvolutionRunArtifactValidator.ValidationError.missingFile(let fileName) {
            throw VerificationError.missingEvolutionArtifact(fileName)
        } catch let error as EvolutionRunArtifactValidator.ValidationError {
            throw VerificationError.invalidEvolutionArtifact(String(describing: error))
        }
    }

    func validatedProjectEvidencePack(in artifactDirectory: URL) throws -> TrainingProjectEvidencePack {
        do {
            return try projectEvidenceStore.load(from: artifactDirectory)
        } catch let error as TrainingProjectEvidencePackArtifactStore.StoreError {
            throw VerificationError.invalidProjectEvidencePack(error)
        }
    }

    func validatedObservabilityArtifact(
        at url: URL
    ) throws -> ConsciousUnconsciousObservabilityArtifact {
        do {
            return try observabilityArtifactStore.validatedArtifact(at: url)
        } catch let error as ConsciousUnconsciousObservabilityArtifactStore.StoreError {
            throw VerificationError.invalidObservabilityArtifact(error)
        }
    }

    func validatedSummaryOutcomeArtifact(
        in artifactDirectory: URL
    ) throws -> TrainingRunSummaryOutcomeArtifact {
        do {
            return try summaryOutcomeStore.validatedArtifact(in: artifactDirectory)
        } catch let error as TrainingRunSummaryOutcomeArtifactStore.StoreError {
            throw VerificationError.invalidSummaryOutcomeArtifact(error)
        }
    }
}
