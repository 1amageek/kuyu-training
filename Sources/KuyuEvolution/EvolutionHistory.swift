import KuyuTrainingContracts
public struct EvolutionHistory<Candidate: Sendable, Fitness: Comparable & Sendable>: Sendable {
    public let generationCount: Int
    public let bestEvaluations: [CandidateEvaluation<Candidate, Fitness>]
    public let latestEvaluations: [CandidateEvaluation<Candidate, Fitness>]

    public init(
        generationCount: Int,
        bestEvaluations: [CandidateEvaluation<Candidate, Fitness>],
        latestEvaluations: [CandidateEvaluation<Candidate, Fitness>]
    ) {
        self.generationCount = max(0, generationCount)
        self.bestEvaluations = bestEvaluations
        self.latestEvaluations = latestEvaluations
    }
}
