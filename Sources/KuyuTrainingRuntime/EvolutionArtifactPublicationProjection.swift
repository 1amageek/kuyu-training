import Foundation
import KuyuEvolution

public struct EvolutionArtifactPublicationProjection: Sendable, Equatable {
    public let accepted: Bool
    public let acceptedCheckpointPath: String?
    public let acceptedCandidateID: String?
    public let bestCheckpointPath: String?
    public let bestCandidateID: String?
    public let reasons: [String]
    public let decisionPath: String

    public init(
        accepted: Bool,
        acceptedCheckpointPath: String?,
        acceptedCandidateID: String?,
        bestCheckpointPath: String?,
        bestCandidateID: String?,
        reasons: [String],
        decisionPath: String
    ) {
        self.accepted = accepted
        self.acceptedCheckpointPath = acceptedCheckpointPath
        self.acceptedCandidateID = acceptedCandidateID
        self.bestCheckpointPath = bestCheckpointPath
        self.bestCandidateID = bestCandidateID
        self.reasons = reasons
        self.decisionPath = decisionPath
    }

    public init(artifacts: EvolutionRunArtifactBundle) {
        self.init(
            accepted: artifacts.acceptedCheckpoint.accepted,
            acceptedCheckpointPath: artifacts.acceptedCheckpoint.checkpointURL?.path,
            acceptedCandidateID: artifacts.acceptedCheckpoint.candidateID,
            bestCheckpointPath: artifacts.acceptedCheckpoint.bestCheckpointURL?.path,
            bestCandidateID: artifacts.acceptedCheckpoint.bestCandidateID,
            reasons: artifacts.acceptedCheckpoint.reasons,
            decisionPath: artifacts.artifactDirectory
                .appendingPathComponent(EvolutionAcceptedCheckpointDecision.fileName)
                .path
        )
    }
}
