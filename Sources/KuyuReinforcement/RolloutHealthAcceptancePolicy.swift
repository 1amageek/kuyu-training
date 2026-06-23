import KuyuTrainingContracts
public struct RolloutHealthAcceptancePolicy: Sendable, Codable, Equatable {
    public let rewardAverageTolerance: Double
    public let stabilityRegressionEnvelope: RolloutStabilityRegressionEnvelope

    public static let conservative = RolloutHealthAcceptancePolicy(
        uncheckedRewardAverageTolerance: 0.02,
        stabilityRegressionEnvelope: .empty
    )

    public static let rootRigidBodyConservative = RolloutHealthAcceptancePolicy(
        uncheckedRewardAverageTolerance: 0.02,
        stabilityRegressionEnvelope: .rootRigidBody(tolerances: .conservative)
    )

    public init(
        rewardAverageTolerance: Double = 0.02,
        stabilityRegressionEnvelope: RolloutStabilityRegressionEnvelope = .empty
    ) throws {
        guard rewardAverageTolerance.isFinite, rewardAverageTolerance >= 0 else {
            throw RolloutHealthAcceptancePolicyError.invalidTolerance
        }
        self.rewardAverageTolerance = rewardAverageTolerance
        self.stabilityRegressionEnvelope = stabilityRegressionEnvelope
    }

    public static func rootRigidBody(
        rewardAverageTolerance: Double = 0.02,
        tolerances: RootRigidBodyStabilityTolerances = .conservative
    ) throws -> RolloutHealthAcceptancePolicy {
        try RolloutHealthAcceptancePolicy(
            rewardAverageTolerance: rewardAverageTolerance,
            stabilityRegressionEnvelope: .rootRigidBody(tolerances: tolerances)
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
        stabilityRegressionEnvelope: RolloutStabilityRegressionEnvelope
    ) {
        rewardAverageTolerance = uncheckedRewardAverageTolerance
        self.stabilityRegressionEnvelope = stabilityRegressionEnvelope
    }
}
