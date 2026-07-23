public enum RolloutHealthProgressRejectionReason: String, Sendable, Codable, Equatable {
    case episodeCountMismatch
    case insufficientEpisodeCount
    case candidateNotRetained
    case noMaterialImprovement
}
