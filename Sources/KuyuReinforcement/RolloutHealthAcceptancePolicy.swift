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
        safetyCostTolerance: Double? = 0.02
    ) throws {
        guard rewardAverageTolerance.isFinite, rewardAverageTolerance >= 0 else {
            throw RolloutHealthAcceptancePolicyError.invalidTolerance
        }
        if let safetyCostTolerance {
            guard safetyCostTolerance.isFinite, safetyCostTolerance >= 0 else {
                throw RolloutHealthAcceptancePolicyError.invalidTolerance
            }
        }
        self.rewardAverageTolerance = rewardAverageTolerance
        self.stabilityRegressionEnvelope = stabilityRegressionEnvelope
        self.safetyCostTolerance = safetyCostTolerance
    }

    public static func rootRigidBody(
        rewardAverageTolerance: Double = 0.02,
        tolerances: RootRigidBodyStabilityTolerances = .conservative,
        safetyCostTolerance: Double? = 0.02
    ) throws -> RolloutHealthAcceptancePolicy {
        try RolloutHealthAcceptancePolicy(
            rewardAverageTolerance: rewardAverageTolerance,
            stabilityRegressionEnvelope: .rootRigidBody(tolerances: tolerances),
            safetyCostTolerance: safetyCostTolerance
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
        if candidate.rewardAverage < baseline.rewardAverage - rewardAverageTolerance {
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
    }
}
