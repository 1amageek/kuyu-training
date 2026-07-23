import Foundation

extension TrainingProjectEvidencePackValidator {
    func validateCheckpoint(
        _ checkpoint: TrainingProjectEvidencePack.CheckpointEvidence
    ) throws {
        guard !checkpoint.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyCheckpointRunID
        }
        guard !checkpoint.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyCheckpointReason
        }
        switch checkpoint.state {
        case .accepted:
            guard let candidateID = checkpoint.candidateCheckpointID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !candidateID.isEmpty else {
                throw ValidationError.acceptedCheckpointMissingCandidateID
            }
            guard checkpoint.hasCandidateCheckpointURL else {
                throw ValidationError.acceptedCheckpointMissingCandidateURL
            }
            guard checkpoint.hasPublishedCheckpointURL else {
                throw ValidationError.acceptedCheckpointMissingPublishedURL
            }
        case .staged:
            guard let candidateID = checkpoint.candidateCheckpointID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !candidateID.isEmpty else {
                throw ValidationError.stagedCheckpointMissingCandidateID
            }
            guard checkpoint.hasCandidateCheckpointURL else {
                throw ValidationError.stagedCheckpointMissingCandidateURL
            }
        case .rejected, .skipped, .failed:
            guard !checkpoint.hasPublishedCheckpointURL else {
                throw ValidationError.nonAcceptedCheckpointHasPublishedURL(checkpoint.state)
            }
        }
    }

    func validateRegressionArtifacts(
        _ artifacts: [TrainingProjectEvidencePack.RegressionArtifactReference]
    ) throws {
        guard !artifacts.isEmpty else { throw ValidationError.emptyRegressionArtifacts }
        var paths: Set<String> = []
        for artifact in artifacts {
            guard !artifact.kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.emptyRegressionArtifactKind
            }
            let path = artifact.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { throw ValidationError.emptyRegressionArtifactPath }
            guard !path.hasPrefix("/") else {
                throw ValidationError.absoluteRegressionArtifactPath(path)
            }
            let components = path.split(separator: "/").map(String.init)
            guard !components.contains("..") else {
                throw ValidationError.escapingRegressionArtifactPath(path)
            }
            guard paths.insert(path).inserted else {
                throw ValidationError.duplicateRegressionArtifactPath(path)
            }
        }
    }
}
