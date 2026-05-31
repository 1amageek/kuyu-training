public struct RolloutHealthAcceptancePolicy: Sendable, Codable, Equatable {
    public let maxOmegaAbsoluteTolerance: Double
    public let maxOmegaRelativeTolerance: Double
    public let maxTiltAbsoluteTolerance: Double
    public let maxTiltRelativeTolerance: Double
    public let rewardAverageTolerance: Double
    public let minAltitudeTolerance: Double

    public static let conservative = RolloutHealthAcceptancePolicy(
        uncheckedMaxOmegaAbsoluteTolerance: 0.25,
        uncheckedMaxOmegaRelativeTolerance: 0.10,
        uncheckedMaxTiltAbsoluteTolerance: 0.05,
        uncheckedMaxTiltRelativeTolerance: 0.10,
        uncheckedRewardAverageTolerance: 0.02,
        uncheckedMinAltitudeTolerance: 0.05
    )

    public init(
        maxOmegaAbsoluteTolerance: Double = 0.25,
        maxOmegaRelativeTolerance: Double = 0.10,
        maxTiltAbsoluteTolerance: Double = 0.05,
        maxTiltRelativeTolerance: Double = 0.10,
        rewardAverageTolerance: Double = 0.02,
        minAltitudeTolerance: Double = 0.05
    ) throws {
        guard maxOmegaAbsoluteTolerance.isFinite, maxOmegaAbsoluteTolerance >= 0,
              maxOmegaRelativeTolerance.isFinite, maxOmegaRelativeTolerance >= 0,
              maxTiltAbsoluteTolerance.isFinite, maxTiltAbsoluteTolerance >= 0,
              maxTiltRelativeTolerance.isFinite, maxTiltRelativeTolerance >= 0,
              rewardAverageTolerance.isFinite, rewardAverageTolerance >= 0,
              minAltitudeTolerance.isFinite, minAltitudeTolerance >= 0 else {
            throw RolloutHealthAcceptancePolicyError.invalidTolerance
        }
        self.maxOmegaAbsoluteTolerance = maxOmegaAbsoluteTolerance
        self.maxOmegaRelativeTolerance = maxOmegaRelativeTolerance
        self.maxTiltAbsoluteTolerance = maxTiltAbsoluteTolerance
        self.maxTiltRelativeTolerance = maxTiltRelativeTolerance
        self.rewardAverageTolerance = rewardAverageTolerance
        self.minAltitudeTolerance = minAltitudeTolerance
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
        if candidate.nonFiniteMetricCount > 0 {
            reasons.append(.nonFiniteMetric)
        }
        if candidate.failureCount > baseline.failureCount {
            reasons.append(.failureCountRegressed)
        }
        if candidate.cancelledCount > baseline.cancelledCount {
            reasons.append(.cancellationCountRegressed)
        }
        if candidate.nonCurriculumTruncationCount > baseline.nonCurriculumTruncationCount {
            reasons.append(.nonCurriculumTruncationRegressed)
        }

        let omegaLimit = max(
            baseline.maxOmega + maxOmegaAbsoluteTolerance,
            baseline.maxOmega * (1 + maxOmegaRelativeTolerance)
        )
        if candidate.maxOmega > omegaLimit {
            reasons.append(.omegaRegressed)
        }

        let tiltLimit = max(
            baseline.maxTilt + maxTiltAbsoluteTolerance,
            baseline.maxTilt * (1 + maxTiltRelativeTolerance)
        )
        if candidate.maxTilt > tiltLimit {
            reasons.append(.tiltRegressed)
        }

        if candidate.rewardAverage < baseline.rewardAverage - rewardAverageTolerance {
            reasons.append(.rewardAverageRegressed)
        }

        if let baselineAltitude = baseline.minAltitude,
           let candidateAltitude = candidate.minAltitude,
           candidateAltitude < baselineAltitude - minAltitudeTolerance {
            reasons.append(.minimumAltitudeRegressed)
        } else if baseline.minAltitude != nil, candidate.minAltitude == nil {
            reasons.append(.minimumAltitudeRegressed)
        }

        return reasons
    }

    private init(
        uncheckedMaxOmegaAbsoluteTolerance: Double,
        uncheckedMaxOmegaRelativeTolerance: Double,
        uncheckedMaxTiltAbsoluteTolerance: Double,
        uncheckedMaxTiltRelativeTolerance: Double,
        uncheckedRewardAverageTolerance: Double,
        uncheckedMinAltitudeTolerance: Double
    ) {
        maxOmegaAbsoluteTolerance = uncheckedMaxOmegaAbsoluteTolerance
        maxOmegaRelativeTolerance = uncheckedMaxOmegaRelativeTolerance
        maxTiltAbsoluteTolerance = uncheckedMaxTiltAbsoluteTolerance
        maxTiltRelativeTolerance = uncheckedMaxTiltRelativeTolerance
        rewardAverageTolerance = uncheckedRewardAverageTolerance
        minAltitudeTolerance = uncheckedMinAltitudeTolerance
    }
}
