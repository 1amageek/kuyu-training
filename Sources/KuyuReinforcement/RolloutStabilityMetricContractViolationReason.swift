import KuyuTrainingContracts
public enum RolloutStabilityMetricContractViolationReason: String, Sendable, Codable, Equatable {
    case emptyMetricID
    case aggregationMismatch
}
