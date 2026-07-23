import Foundation
import KuyuTrainingContracts

public enum EvolutionRunEvent: Sendable, Equatable {
    case started(EvolutionRunManifest)
    case populationSeeded(EvolutionPopulation)
    case generationStarted(Int)
    case candidateEvaluated(FitnessSummary)
    case candidateAcceptanceStarted(generationIndex: Int, candidateID: String)
    case candidateAcceptanceCompleted(EvolutionCandidateAcceptanceRecord)
    case generationCompleted(PopulationGenerationRecord)
    case completed(EvolutionRunResult)
}
