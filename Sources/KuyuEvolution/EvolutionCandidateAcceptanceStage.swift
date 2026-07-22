import KuyuTrainingContracts

public struct EvolutionCandidateAcceptanceStage: Sendable {
    public let evaluator: any EvolutionCandidateAcceptanceEvaluating
    public let gatePolicy: EvolutionGatePolicy
    public let promotionCriterion: TrainingPromotionCriterion

    public init(
        evaluator: any EvolutionCandidateAcceptanceEvaluating,
        gatePolicy: EvolutionGatePolicy,
        promotionCriterion: TrainingPromotionCriterion = .incumbentRelative
    ) {
        self.evaluator = evaluator
        self.gatePolicy = gatePolicy
        self.promotionCriterion = promotionCriterion
    }
}
