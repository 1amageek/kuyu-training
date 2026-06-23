import KuyuTrainingContracts
public enum EvolutionContinuationDecision: Sendable, Equatable {
    case continueSearch(reason: String)
    case converged(reason: String)
    case stopped(reason: String)
}
