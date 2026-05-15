public protocol EvolutionStrategy: Sendable {
    associatedtype Candidate: Sendable
    associatedtype Fitness: Comparable & Sendable

    func select(
        from evaluations: [CandidateEvaluation<Candidate, Fitness>],
        policy: SelectionPolicy
    ) throws -> [Candidate]

    func shouldContinue(
        history: EvolutionHistory<Candidate, Fitness>,
        policy: ConvergencePolicy
    ) -> EvolutionContinuationDecision
}
