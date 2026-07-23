import Foundation
import KuyuTrainingValidation

public extension GeneratedTrainingArtifactCompatibilityVerifier {
    func validatedCheckpointEvaluationArtifact(
        _ request: CheckpointEvaluationArtifactCompatibilityRequest
    ) throws -> CheckpointEvaluationArtifact {
        let url = request.artifactDirectory.appendingPathComponent(CheckpointEvaluationArtifact.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VerificationError.missingCheckpointEvaluationArtifact(CheckpointEvaluationArtifact.fileName)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let artifact = try decoder.decode(CheckpointEvaluationArtifact.self, from: Data(contentsOf: url))
        try validateCheckpointEvaluationArtifact(
            artifact,
            expectedProfile: request.expectedProfile,
            expectedCheckpointPath: request.expectedCheckpointPath,
            requiresPolicyPass: request.requiresPolicyPass
        )
        return artifact
    }

    func validateCheckpointEvaluationArtifact(
        _ artifact: CheckpointEvaluationArtifact,
        expectedProfile: TaskEvaluationProfile,
        expectedCheckpointPath: String,
        requiresPolicyPass: Bool
    ) throws {
        do {
            try CheckpointEvaluationArtifactValidator.validate(
                artifact,
                expectedProfile: expectedProfile,
                expectedCheckpointPath: expectedCheckpointPath,
                requiresPolicyPass: requiresPolicyPass
            )
        } catch let error as CheckpointEvaluationArtifactValidator.ValidationError {
            throw VerificationError.invalidCheckpointEvaluationArtifact(
                CheckpointEvaluationArtifactCompatibilityFailure(validationError: error)
            )
        }
    }
}
