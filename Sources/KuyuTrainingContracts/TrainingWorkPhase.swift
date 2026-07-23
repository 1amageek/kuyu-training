public enum TrainingWorkPhase: String, Codable, Sendable, Hashable {
    case screening
    case refinement
    case refinementBackfill
    case rollout
    case optimization
    case candidateGate
    case artifactPublication
}
