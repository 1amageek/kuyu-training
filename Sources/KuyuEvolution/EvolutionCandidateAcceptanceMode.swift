import Foundation

public enum EvolutionCandidateAcceptanceMode: String, Sendable, Codable, Equatable {
    case searchGateOnly
    case dedicatedEvaluation
    /// Dedicated acceptance evaluation judged on the absolute gate only
    /// (curriculum-rung promotion; see TrainingPromotionCriterion).
    case dedicatedAbsoluteThreshold
}
