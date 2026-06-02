public struct RolloutStabilityMetricContractViolation: Sendable, Codable, Equatable {
    public let metricID: RolloutStabilityMetricID
    public let reason: RolloutStabilityMetricContractViolationReason

    public init(
        metricID: RolloutStabilityMetricID,
        reason: RolloutStabilityMetricContractViolationReason
    ) {
        self.metricID = metricID
        self.reason = reason
    }
}
