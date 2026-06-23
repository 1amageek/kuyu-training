import KuyuTrainingContracts
public struct RolloutStabilityLimitEnvelope: Sendable, Codable, Equatable {
    public let checks: [RolloutStabilityLimitCheck]

    public static let unbounded = RolloutStabilityLimitEnvelope(uncheckedChecks: [])

    public init(checks: [RolloutStabilityLimitCheck]) throws {
        var metricIDs: Set<RolloutStabilityMetricID> = []
        for check in checks {
            guard !metricIDs.contains(check.metricID) else {
                throw RolloutStabilityRegressionContractError.duplicateMetricID(check.metricID)
            }
            metricIDs.insert(check.metricID)
        }
        self.checks = checks
    }

    init(uncheckedChecks checks: [RolloutStabilityLimitCheck]) {
        self.checks = checks
    }

    public static func rootRigidBody(
        maximumAngularRate: Double? = nil,
        maximumAttitudeDeviation: Double? = nil,
        minimumRootAltitude: Double? = nil
    ) throws -> RolloutStabilityLimitEnvelope {
        var checks: [RolloutStabilityLimitCheck] = []
        if let maximumAngularRate {
            checks.append(try RolloutStabilityLimitCheck(
                metricID: .maximumAngularRate,
                direction: .upperBound,
                limit: maximumAngularRate,
                rejectionReason: .omegaRegressed
            ))
        }
        if let maximumAttitudeDeviation {
            checks.append(try RolloutStabilityLimitCheck(
                metricID: .maximumAttitudeDeviation,
                direction: .upperBound,
                limit: maximumAttitudeDeviation,
                rejectionReason: .tiltRegressed
            ))
        }
        if let minimumRootAltitude {
            checks.append(try RolloutStabilityLimitCheck(
                metricID: .minimumRootAltitude,
                direction: .lowerBound,
                limit: minimumRootAltitude,
                rejectionReason: .minimumAltitudeRegressed
            ))
        }
        return try RolloutStabilityLimitEnvelope(checks: checks)
    }

    public func rejectionReasons(health: RolloutHealth) -> [RolloutHealthRejectionReason] {
        checks.compactMap { $0.rejectionReason(health: health) }
    }
}
