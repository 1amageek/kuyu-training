public struct TrainingProjectCheckpointEvidence: Sendable, Codable, Equatable {
    public let runID: String
    public let state: CheckpointDecisionState
    public let reason: String
    public let candidateCheckpointID: String?
    public let hasCandidateCheckpointURL: Bool
    public let hasPublishedCheckpointURL: Bool
    public let candidateCheckpointPath: String?
    public let candidateCheckpointSHA256Digest: String?
    public let publishedCheckpointPath: String?
    public let publishedCheckpointSHA256Digest: String?

    public init(
        runID: String,
        state: CheckpointDecisionState,
        reason: String,
        candidateCheckpointID: String?,
        hasCandidateCheckpointURL: Bool,
        hasPublishedCheckpointURL: Bool,
        candidateCheckpointPath: String? = nil,
        candidateCheckpointSHA256Digest: String? = nil,
        publishedCheckpointPath: String? = nil,
        publishedCheckpointSHA256Digest: String? = nil
    ) {
        self.runID = runID
        self.state = state
        self.reason = reason
        self.candidateCheckpointID = candidateCheckpointID
        self.hasCandidateCheckpointURL = hasCandidateCheckpointURL
        self.hasPublishedCheckpointURL = hasPublishedCheckpointURL
        self.candidateCheckpointPath = candidateCheckpointPath
        self.candidateCheckpointSHA256Digest = candidateCheckpointSHA256Digest
        self.publishedCheckpointPath = publishedCheckpointPath
        self.publishedCheckpointSHA256Digest = publishedCheckpointSHA256Digest
    }

    public init(
        decision: CheckpointDecision,
        candidateCheckpointPath: String? = nil,
        candidateCheckpointSHA256Digest: String? = nil,
        publishedCheckpointPath: String? = nil,
        publishedCheckpointSHA256Digest: String? = nil
    ) {
        self.init(
            runID: decision.runID,
            state: decision.state,
            reason: decision.reason,
            candidateCheckpointID: decision.candidateCheckpointID,
            hasCandidateCheckpointURL: decision.candidateCheckpointURL != nil,
            hasPublishedCheckpointURL: decision.publishedCheckpointURL != nil,
            candidateCheckpointPath: candidateCheckpointPath ?? decision.candidateCheckpointURL?.path,
            candidateCheckpointSHA256Digest: candidateCheckpointSHA256Digest,
            publishedCheckpointPath: publishedCheckpointPath ?? decision.publishedCheckpointURL?.path,
            publishedCheckpointSHA256Digest: publishedCheckpointSHA256Digest
        )
    }
}
