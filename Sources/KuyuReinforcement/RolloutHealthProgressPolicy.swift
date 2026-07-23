public struct RolloutHealthProgressPolicy: Sendable, Codable, Equatable {
    public let minimumEpisodeCount: Int
    public let minimumRewardAverageImprovement: Double
    public let stabilityToleranceScale: Double

    public static let conservative = RolloutHealthProgressPolicy(
        uncheckedMinimumEpisodeCount: 1,
        minimumRewardAverageImprovement: 0.01,
        stabilityToleranceScale: 1
    )

    public init(
        minimumEpisodeCount: Int,
        minimumRewardAverageImprovement: Double = 0.01,
        stabilityToleranceScale: Double = 1
    ) throws {
        guard minimumEpisodeCount > 0 else {
            throw RolloutHealthProgressPolicyError
                .invalidMinimumEpisodeCount(minimumEpisodeCount)
        }
        guard minimumRewardAverageImprovement.isFinite,
              minimumRewardAverageImprovement > 0 else {
            throw RolloutHealthProgressPolicyError
                .invalidRewardAverageImprovement(minimumRewardAverageImprovement)
        }
        guard stabilityToleranceScale.isFinite, stabilityToleranceScale > 0 else {
            throw RolloutHealthProgressPolicyError
                .invalidStabilityToleranceScale(stabilityToleranceScale)
        }
        self.minimumEpisodeCount = minimumEpisodeCount
        self.minimumRewardAverageImprovement = minimumRewardAverageImprovement
        self.stabilityToleranceScale = stabilityToleranceScale
    }

    public func assessment(
        candidate: RolloutHealth,
        relativeTo baseline: RolloutHealth,
        retentionRejectionReasons: [RolloutHealthRejectionReason],
        stabilityRegressionEnvelope: RolloutStabilityRegressionEnvelope
    ) -> RolloutHealthProgressAssessment {
        var signals: [RolloutHealthProgressSignal] = []
        if candidate.failureCount < baseline.failureCount {
            signals.append(.failureCountReduced)
        }
        if candidate.nonHorizonTruncationCount < baseline.nonHorizonTruncationCount {
            signals.append(.nonHorizonTruncationCountReduced)
        }
        let rewardAverageDelta = candidate.rewardAverage - baseline.rewardAverage
        if rewardAverageDelta >= minimumRewardAverageImprovement {
            signals.append(.rewardAverageImproved)
        }
        signals.append(contentsOf: stabilityRegressionEnvelope.materiallyImprovedMetricIDs(
            candidate: candidate,
            relativeTo: baseline,
            toleranceScale: stabilityToleranceScale
        ).map(RolloutHealthProgressSignal.stabilityMetricImproved))

        var reasons: [RolloutHealthProgressRejectionReason] = []
        if candidate.episodeCount != baseline.episodeCount {
            reasons.append(.episodeCountMismatch)
        }
        if baseline.episodeCount < minimumEpisodeCount
            || candidate.episodeCount < minimumEpisodeCount {
            reasons.append(.insufficientEpisodeCount)
        }
        if !retentionRejectionReasons.isEmpty {
            reasons.append(.candidateNotRetained)
        }
        if signals.isEmpty {
            reasons.append(.noMaterialImprovement)
        }
        return RolloutHealthProgressAssessment(
            baselineEpisodeCount: baseline.episodeCount,
            candidateEpisodeCount: candidate.episodeCount,
            failureCountDelta: candidate.failureCount - baseline.failureCount,
            nonHorizonTruncationCountDelta: candidate.nonHorizonTruncationCount
                - baseline.nonHorizonTruncationCount,
            rewardAverageDelta: rewardAverageDelta,
            retentionRejectionReasons: retentionRejectionReasons,
            progressSignals: signals,
            progressRejectionReasons: reasons
        )
    }

    private init(
        uncheckedMinimumEpisodeCount minimumEpisodeCount: Int,
        minimumRewardAverageImprovement: Double,
        stabilityToleranceScale: Double
    ) {
        self.minimumEpisodeCount = minimumEpisodeCount
        self.minimumRewardAverageImprovement = minimumRewardAverageImprovement
        self.stabilityToleranceScale = stabilityToleranceScale
    }
}
