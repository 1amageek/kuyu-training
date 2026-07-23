import KuyuTrainingContracts

public protocol EvolutionCandidateAcceptanceEvaluating: Sendable {
    func evaluateAcceptance(
        request: EvolutionCandidateAcceptanceRequest,
        progressReporter: (any TrainingProgressReporting)?
    ) async throws -> EvolutionCandidateAcceptanceResult
}
