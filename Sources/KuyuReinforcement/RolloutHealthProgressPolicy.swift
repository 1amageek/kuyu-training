public struct RolloutHealthProgressPolicy: Sendable, Codable, Equatable {
    public let minimumEpisodeCount: Int
    public let minimumRewardAverageImprovement: Double
    public let stabilityToleranceScale: Double
    /// When set, a candidate whose summed episode safety cost falls below
    /// baseline * (1 - fraction) counts as material progress
    /// (safetyCostReduced). Under an active Lagrangian constraint violation,
    /// cost descent IS the training objective; without this signal a
    /// candidate that buys a real cost reduction with a tolerated reward
    /// loss can never be selected. nil disables the signal, which is also
    /// how policies recorded before this field existed replay.
    public let minimumSafetyCostImprovementFraction: Double?

    public static let conservative = RolloutHealthProgressPolicy(
        uncheckedMinimumEpisodeCount: 1,
        minimumRewardAverageImprovement: 0.01,
        stabilityToleranceScale: 1
    )

    public init(
        minimumEpisodeCount: Int,
        minimumRewardAverageImprovement: Double = 0.01,
        stabilityToleranceScale: Double = 1,
        minimumSafetyCostImprovementFraction: Double? = nil
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
        if let minimumSafetyCostImprovementFraction {
            guard minimumSafetyCostImprovementFraction.isFinite,
                  minimumSafetyCostImprovementFraction > 0,
                  minimumSafetyCostImprovementFraction < 1 else {
                throw RolloutHealthProgressPolicyError
                    .invalidSafetyCostImprovementFraction(minimumSafetyCostImprovementFraction)
            }
        }
        self.minimumEpisodeCount = minimumEpisodeCount
        self.minimumRewardAverageImprovement = minimumRewardAverageImprovement
        self.stabilityToleranceScale = stabilityToleranceScale
        self.minimumSafetyCostImprovementFraction = minimumSafetyCostImprovementFraction
    }

    public func assessment(
        candidate: RolloutHealth,
        relativeTo baseline: RolloutHealth,
        retentionRejectionReasons: [RolloutHealthRejectionReason],
        stabilityRegressionEnvelope: RolloutStabilityRegressionEnvelope,
        candidateEpisodeSafetyCost: Double? = nil,
        baselineEpisodeSafetyCost: Double? = nil
    ) -> RolloutHealthProgressAssessment {
        var signals: [RolloutHealthProgressSignal] = []
        if let fraction = minimumSafetyCostImprovementFraction,
           let candidateCost = candidateEpisodeSafetyCost,
           let baselineCost = baselineEpisodeSafetyCost,
           baselineCost > 0,
           candidateCost <= baselineCost * (1 - fraction) {
            signals.append(.safetyCostReduced)
        }
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
        minimumSafetyCostImprovementFraction = nil
    }
}
