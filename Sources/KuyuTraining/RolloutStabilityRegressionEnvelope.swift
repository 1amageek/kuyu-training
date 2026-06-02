public struct RolloutStabilityRegressionEnvelope: Sendable, Equatable {
    public let checks: [RolloutStabilityRegressionCheck]

    public init(checks: [RolloutStabilityRegressionCheck]) throws {
        var metricIDs: Set<RolloutStabilityMetricID> = []
        for check in checks {
            guard !metricIDs.contains(check.metricID) else {
                throw RolloutStabilityRegressionContractError.duplicateMetricID(check.metricID)
            }
            metricIDs.insert(check.metricID)
        }
        self.checks = checks
    }

    init(uncheckedChecks checks: [RolloutStabilityRegressionCheck]) {
        self.checks = checks
    }

    public static func rootRigidBody(policy: RolloutHealthAcceptancePolicy) -> RolloutStabilityRegressionEnvelope {
        RolloutStabilityRegressionEnvelope(uncheckedChecks: [
            RolloutStabilityRegressionCheck(
                uncheckedMetricID: .maximumAngularRate,
                direction: .upperBound,
                absoluteTolerance: policy.maxOmegaAbsoluteTolerance,
                relativeTolerance: policy.maxOmegaRelativeTolerance,
                rejectionReason: .omegaRegressed
            ),
            RolloutStabilityRegressionCheck(
                uncheckedMetricID: .maximumAttitudeDeviation,
                direction: .upperBound,
                absoluteTolerance: policy.maxTiltAbsoluteTolerance,
                relativeTolerance: policy.maxTiltRelativeTolerance,
                rejectionReason: .tiltRegressed
            ),
            RolloutStabilityRegressionCheck(
                uncheckedMetricID: .minimumRootAltitude,
                direction: .lowerBound,
                absoluteTolerance: policy.minAltitudeTolerance,
                relativeTolerance: 0,
                rejectionReason: .minimumAltitudeRegressed
            ),
        ])
    }

    public func rejectionReasons(
        candidate: RolloutHealth,
        relativeTo baseline: RolloutHealth
    ) -> [RolloutHealthRejectionReason] {
        checks.compactMap { $0.rejectionReason(candidate: candidate, relativeTo: baseline) }
    }

    public func hasDirectionalImprovement(
        candidate: RolloutHealth,
        relativeTo baseline: RolloutHealth
    ) -> Bool {
        checks.contains {
            $0.isDirectionallyImproved(candidate: candidate, relativeTo: baseline)
        }
    }
}
