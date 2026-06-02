public enum RolloutHealthRejectionReason: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case episodeCountMismatch
    case nonFiniteMetric
    case failureCountRegressed
    case cancellationCountRegressed
    case nonHorizonTruncationRegressed
    case omegaRegressed
    case tiltRegressed
    case rewardAverageRegressed
    case minimumAltitudeRegressed
    case stabilityMetricRegressed
    case stabilityMetricMissing
    case stabilityMetricContractViolation
}
