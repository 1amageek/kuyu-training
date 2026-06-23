import KuyuTrainingContracts
public struct DefaultEvolutionStrategy<Candidate: Sendable, Fitness: Comparable & Sendable>: EvolutionStrategy {
    public init() {}

    public func select(
        from evaluations: [CandidateEvaluation<Candidate, Fitness>],
        policy: SelectionPolicy
    ) throws -> [Candidate] {
        Array(
            evaluations
                .sorted { $0.fitness > $1.fitness }
                .prefix(policy.parentCount)
                .map(\.candidate)
        )
    }

    public func shouldContinue(
        history: EvolutionHistory<Candidate, Fitness>,
        policy: ConvergencePolicy
    ) -> EvolutionContinuationDecision {
        guard history.bestEvaluations.count >= policy.patienceGenerations else {
            return .continueSearch(reason: "patience-window-not-filled")
        }
        let window = history.bestEvaluations.suffix(policy.patienceGenerations)
        guard let first = window.first?.fitness,
              let last = window.last?.fitness else {
            return .continueSearch(reason: "missing-fitness-window")
        }
        if last > first {
            return .continueSearch(reason: "fitness-improving")
        }
        return .converged(reason: "fitness-not-improving")
    }
}
