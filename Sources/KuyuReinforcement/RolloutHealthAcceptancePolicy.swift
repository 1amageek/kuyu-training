import KuyuTrainingContracts
public struct RolloutHealthAcceptancePolicy: Sendable, Codable, Equatable {
    public let rewardAverageTolerance: Double
    public let stabilityRegressionEnvelope: RolloutStabilityRegressionEnvelope
    /// Relative tolerance for the episode safety-cost regression comparison
    /// performed by checkpoint comparison consumers: a candidate regresses
    /// only when its summed episode safety cost exceeds
    /// baseline * (1 + tolerance). nil means strict zero tolerance, which is
    /// also how policies embedded in artifacts recorded before this field
    /// existed are replayed. A zero-tolerance point comparison on a noisy
    /// scalar rejected every long-rollout candidate (0.19% cost delta versus
    /// per-iteration rollout noise two orders of magnitude larger), so
    /// consumers should compare through `effectiveSafetyCostTolerance`.
    public let safetyCostTolerance: Double?
    /// Relative tolerance for the reward-average regression check, as a
    /// fraction of |baseline.rewardAverage|. The absolute
    /// rewardAverageTolerance was sized for O(1) rewards; at reward
    /// magnitudes of 10^3-10^4 it acts as zero tolerance and vetoes
    /// candidates that trade a fraction of a percent of reward for a real
    /// safety-cost reduction. The effective tolerance is
    /// max(rewardAverageTolerance, |baseline| * rewardAverageRelativeTolerance).
    /// nil keeps the absolute-only comparison (and is how policies recorded
    /// before this field existed replay).
    public let rewardAverageRelativeTolerance: Double?

    public static let conservative = RolloutHealthAcceptancePolicy(
        uncheckedRewardAverageTolerance: 0.02,
        stabilityRegressionEnvelope: .empty,
        safetyCostTolerance: 0.02
    )

    public static let rootRigidBodyConservative = RolloutHealthAcceptancePolicy(
        uncheckedRewardAverageTolerance: 0.02,
        stabilityRegressionEnvelope: .rootRigidBody(tolerances: .conservative),
        safetyCostTolerance: 0.02
    )

    public var effectiveSafetyCostTolerance: Double {
        safetyCostTolerance ?? 0
    }

    public init(
        rewardAverageTolerance: Double = 0.02,
        stabilityRegressionEnvelope: RolloutStabilityRegressionEnvelope = .empty,
        safetyCostTolerance: Double? = 0.02,
        rewardAverageRelativeTolerance: Double? = nil
    ) throws {
        guard rewardAverageTolerance.isFinite, rewardAverageTolerance >= 0 else {
            throw RolloutHealthAcceptancePolicyError.invalidTolerance
        }
        if let safetyCostTolerance {
            guard safetyCostTolerance.isFinite, safetyCostTolerance >= 0 else {
                throw RolloutHealthAcceptancePolicyError.invalidTolerance
            }
        }
        if let rewardAverageRelativeTolerance {
            guard rewardAverageRelativeTolerance.isFinite,
                  rewardAverageRelativeTolerance >= 0,
                  rewardAverageRelativeTolerance < 1 else {
                throw RolloutHealthAcceptancePolicyError.invalidTolerance
            }
        }
        self.rewardAverageTolerance = rewardAverageTolerance
        self.stabilityRegressionEnvelope = stabilityRegressionEnvelope
        self.safetyCostTolerance = safetyCostTolerance
        self.rewardAverageRelativeTolerance = rewardAverageRelativeTolerance
    }

    public static func rootRigidBody(
        rewardAverageTolerance: Double = 0.02,
        tolerances: RootRigidBodyStabilityTolerances = .conservative,
        safetyCostTolerance: Double? = 0.02,
        rewardAverageRelativeTolerance: Double? = nil
    ) throws -> RolloutHealthAcceptancePolicy {
        try RolloutHealthAcceptancePolicy(
            rewardAverageTolerance: rewardAverageTolerance,
            stabilityRegressionEnvelope: .rootRigidBody(tolerances: tolerances),
            safetyCostTolerance: safetyCostTolerance,
            rewardAverageRelativeTolerance: rewardAverageRelativeTolerance
        )
    }

    public func effectiveRewardAverageTolerance(
        baselineRewardAverage: Double
    ) -> Double {
        max(
            rewardAverageTolerance,
            abs(baselineRewardAverage) * (rewardAverageRelativeTolerance ?? 0)
        )
    }

    public func accepts(candidate: RolloutHealth, relativeTo baseline: RolloutHealth) -> Bool {
        rejectionReasons(candidate: candidate, relativeTo: baseline).isEmpty
    }

    public func rejectionReasons(
        candidate: RolloutHealth,
        relativeTo baseline: RolloutHealth
    ) -> [RolloutHealthRejectionReason] {
        var reasons: [RolloutHealthRejectionReason] = []
        if candidate.episodeCount != baseline.episodeCount {
            reasons.append(.episodeCountMismatch)
        }
        for reason in candidate.trainingDecisionContractRejectionReasons {
            appendUnique(reason, to: &reasons)
        }
        for reason in baseline.trainingDecisionContractRejectionReasons {
            appendUnique(reason, to: &reasons)
        }
        if candidate.failureCount > baseline.failureCount {
            reasons.append(.failureCountRegressed)
        }
        if candidate.cancelledCount > baseline.cancelledCount {
            reasons.append(.cancellationCountRegressed)
        }
        if candidate.nonHorizonTruncationCount > baseline.nonHorizonTruncationCount {
            reasons.append(.nonHorizonTruncationRegressed)
        }
        appendUnique(
            stabilityRegressionEnvelope.rejectionReasons(candidate: candidate, relativeTo: baseline),
            to: &reasons
        )
        if candidate.rewardAverage < baseline.rewardAverage
            - effectiveRewardAverageTolerance(baselineRewardAverage: baseline.rewardAverage) {
            reasons.append(.rewardAverageRegressed)
        }
        return reasons
    }

    private func appendUnique(
        _ newReasons: [RolloutHealthRejectionReason],
        to reasons: inout [RolloutHealthRejectionReason]
    ) {
        for reason in newReasons {
            appendUnique(reason, to: &reasons)
        }
    }

    private func appendUnique(
        _ reason: RolloutHealthRejectionReason,
        to reasons: inout [RolloutHealthRejectionReason]
    ) {
        if !reasons.contains(reason) {
            reasons.append(reason)
        }
    }

    private init(
        uncheckedRewardAverageTolerance: Double,
        stabilityRegressionEnvelope: RolloutStabilityRegressionEnvelope,
        safetyCostTolerance: Double?
    ) {
        rewardAverageTolerance = uncheckedRewardAverageTolerance
        self.stabilityRegressionEnvelope = stabilityRegressionEnvelope
        self.safetyCostTolerance = safetyCostTolerance
        rewardAverageRelativeTolerance = nil
    }
}
