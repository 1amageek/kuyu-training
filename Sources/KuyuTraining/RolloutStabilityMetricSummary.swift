public struct RolloutStabilityMetricSummary: Sendable, Codable, Equatable {
    public let id: RolloutStabilityMetricID
    public let aggregation: RolloutStabilityMetricAggregation
    public let value: Double

    public init(
        id: RolloutStabilityMetricID,
        aggregation: RolloutStabilityMetricAggregation,
        value: Double
    ) {
        self.id = id
        self.aggregation = aggregation
        self.value = value
    }
}
