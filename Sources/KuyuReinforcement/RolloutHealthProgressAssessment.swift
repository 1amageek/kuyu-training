public struct RolloutHealthProgressAssessment: Sendable, Codable, Equatable {
    public let baselineEpisodeCount: Int
    public let candidateEpisodeCount: Int
    public let failureCountDelta: Int
    public let nonHorizonTruncationCountDelta: Int
    public let rewardAverageDelta: Double
    public let retentionRejectionReasons: [RolloutHealthRejectionReason]
    public let progressSignals: [RolloutHealthProgressSignal]
    public let progressRejectionReasons: [RolloutHealthProgressRejectionReason]

    public init(
        baselineEpisodeCount: Int,
        candidateEpisodeCount: Int,
        failureCountDelta: Int,
        nonHorizonTruncationCountDelta: Int,
        rewardAverageDelta: Double,
        retentionRejectionReasons: [RolloutHealthRejectionReason],
        progressSignals: [RolloutHealthProgressSignal],
        progressRejectionReasons: [RolloutHealthProgressRejectionReason]
    ) {
        self.baselineEpisodeCount = baselineEpisodeCount
        self.candidateEpisodeCount = candidateEpisodeCount
        self.failureCountDelta = failureCountDelta
        self.nonHorizonTruncationCountDelta = nonHorizonTruncationCountDelta
        self.rewardAverageDelta = rewardAverageDelta
        self.retentionRejectionReasons = retentionRejectionReasons
        self.progressSignals = progressSignals
        self.progressRejectionReasons = progressRejectionReasons
    }

    public var qualified: Bool {
        retentionRejectionReasons.isEmpty && progressRejectionReasons.isEmpty
    }
}
