import KuyuTrainingContracts
public struct RolloutStabilityLimitCheck: Sendable, Codable, Equatable {
    public let metricID: RolloutStabilityMetricID
    public let direction: RolloutStabilityRegressionDirection
    public let limit: Double
    public let rejectionReason: RolloutHealthRejectionReason

    public init(
        metricID: RolloutStabilityMetricID,
        direction: RolloutStabilityRegressionDirection,
        limit: Double,
        rejectionReason: RolloutHealthRejectionReason
    ) throws {
        guard !metricID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RolloutStabilityRegressionContractError.emptyMetricID
        }
        guard limit.isFinite else {
            throw RolloutStabilityRegressionContractError.invalidTolerance
        }
        self.metricID = metricID
        self.direction = direction
        self.limit = limit
        self.rejectionReason = rejectionReason
    }

    public func rejectionReason(health: RolloutHealth) -> RolloutHealthRejectionReason? {
        guard let value = health.stabilityMetricValue(metricID) else {
            return .stabilityMetricMissing
        }
        switch direction {
        case .upperBound:
            return value > limit ? rejectionReason : nil
        case .lowerBound:
            return value < limit ? rejectionReason : nil
        }
    }
}
