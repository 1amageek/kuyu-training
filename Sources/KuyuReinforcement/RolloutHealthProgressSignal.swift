public enum RolloutHealthProgressSignal: Sendable, Codable, Equatable {
    case failureCountReduced
    case nonHorizonTruncationCountReduced
    case rewardAverageImproved
    case safetyCostReduced
    case stabilityMetricImproved(RolloutStabilityMetricID)

    public var identifier: String {
        switch self {
        case .failureCountReduced:
            return "failure-count-reduced"
        case .nonHorizonTruncationCountReduced:
            return "non-horizon-truncation-count-reduced"
        case .rewardAverageImproved:
            return "reward-average-improved"
        case .safetyCostReduced:
            return "safety-cost-reduced"
        case .stabilityMetricImproved(let metricID):
            return "stability-metric-improved:\(metricID.rawValue)"
        }
    }
}
