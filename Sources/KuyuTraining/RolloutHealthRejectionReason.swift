public enum RolloutHealthRejectionReason: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case episodeCountMismatch
    case nonFiniteMetric
    case failureCountRegressed
    case cancellationCountRegressed
    case nonCurriculumTruncationRegressed
    case omegaRegressed
    case tiltRegressed
    case rewardAverageRegressed
    case minimumAltitudeRegressed
}
