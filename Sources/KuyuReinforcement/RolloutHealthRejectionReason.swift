import KuyuTrainingContracts
public enum RolloutHealthRejectionReason: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case episodeCountMismatch
    case nonFiniteMetric
    case failureCountRegressed
    case safetyFailureRegressed
    case safetyCostRegressed
    case cancellationCountRegressed
    case nonHorizonTruncationRegressed
    case omegaRegressed
    case tiltRegressed
    case rewardAverageRegressed
    case survivalStepRegressed
    case minimumAltitudeRegressed
    case stabilityMetricRegressed
    case stabilityMetricMissing
    case stabilityMetricContractViolation
}
