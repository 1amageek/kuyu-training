import Foundation
import KuyuTrainingValidation

public struct CheckpointEvaluationArtifactCompatibilityRequest: Sendable, Equatable {
    public let artifactDirectory: URL
    public let expectedProfile: TaskEvaluationProfile
    public let expectedCheckpointPath: String
    public let requiresPolicyPass: Bool

    public init(
        artifactDirectory: URL,
        expectedProfile: TaskEvaluationProfile,
        expectedCheckpointPath: String,
        requiresPolicyPass: Bool
    ) {
        self.artifactDirectory = artifactDirectory
        self.expectedProfile = expectedProfile
        self.expectedCheckpointPath = expectedCheckpointPath
        self.requiresPolicyPass = requiresPolicyPass
    }
}
