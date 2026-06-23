import KuyuTrainingContracts
public enum RolloutStabilityRegressionContractError: Error, Sendable, Equatable {
    case emptyMetricID
    case invalidTolerance
    case duplicateMetricID(RolloutStabilityMetricID)
}
