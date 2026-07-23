import KuyuTrainingContracts
public struct RolloutStabilityRegressionEnvelope: Sendable, Codable, Equatable {
    public let checks: [RolloutStabilityRegressionCheck]

    public static let empty = RolloutStabilityRegressionEnvelope(uncheckedChecks: [])

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

    public static func rootRigidBody(
        tolerances: RootRigidBodyStabilityTolerances
    ) -> RolloutStabilityRegressionEnvelope {
        RolloutStabilityRegressionEnvelope(uncheckedChecks: [
            RolloutStabilityRegressionCheck(
                uncheckedMetricID: .maximumAngularRate,
                direction: .upperBound,
                absoluteTolerance: tolerances.maxAngularRateAbsoluteTolerance,
                relativeTolerance: tolerances.maxAngularRateRelativeTolerance,
                rejectionReason: .omegaRegressed
            ),
            RolloutStabilityRegressionCheck(
                uncheckedMetricID: .maximumAttitudeDeviation,
                direction: .upperBound,
                absoluteTolerance: tolerances.maxAttitudeDeviationAbsoluteTolerance,
                relativeTolerance: tolerances.maxAttitudeDeviationRelativeTolerance,
                rejectionReason: .tiltRegressed
            ),
            RolloutStabilityRegressionCheck(
                uncheckedMetricID: .minimumRootAltitude,
                direction: .lowerBound,
                absoluteTolerance: tolerances.minRootAltitudeTolerance,
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

    public func hasMaterialDirectionalImprovement(
        candidate: RolloutHealth,
        relativeTo baseline: RolloutHealth,
        toleranceScale: Double
    ) -> Bool {
        !materiallyImprovedMetricIDs(
            candidate: candidate,
            relativeTo: baseline,
            toleranceScale: toleranceScale
        ).isEmpty
    }

    public func materiallyImprovedMetricIDs(
        candidate: RolloutHealth,
        relativeTo baseline: RolloutHealth,
        toleranceScale: Double
    ) -> [RolloutStabilityMetricID] {
        checks.compactMap {
            $0.isMateriallyDirectionallyImproved(
                candidate: candidate,
                relativeTo: baseline,
                toleranceScale: toleranceScale
            ) ? $0.metricID : nil
        }
    }
}
