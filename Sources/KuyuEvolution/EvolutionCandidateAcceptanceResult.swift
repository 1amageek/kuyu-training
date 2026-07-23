import KuyuTrainingContracts

public struct EvolutionCandidateAcceptanceResult: Sendable, Equatable {
    public let fitness: FitnessSummary
    public let incumbentFitness: FitnessSummary
    public let evaluationContract: EvolutionCandidateAcceptanceEvaluationContract
    public let evidence: [EvolutionCandidateAcceptanceEvidenceReference]

    public init(
        fitness: FitnessSummary,
        incumbentFitness: FitnessSummary,
        evaluationContract: EvolutionCandidateAcceptanceEvaluationContract,
        evidence: [EvolutionCandidateAcceptanceEvidenceReference]
    ) {
        self.fitness = fitness
        self.incumbentFitness = incumbentFitness
        self.evaluationContract = evaluationContract
        self.evidence = evidence
    }
}
