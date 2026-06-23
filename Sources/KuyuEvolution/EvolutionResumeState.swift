import Foundation
import KuyuTrainingContracts

/// Rehydrated in-memory state assembled from the durable generation checkpoints
/// `0...lastCommittedGeneration`. Fed to `EvolutionRunOrchestrator.run` to
/// continue an interrupted run from `startGenerationIndex` without re-seeding or
/// recomputing committed generations.
public struct EvolutionResumeState: Sendable, Equatable {
    /// Run identifier of the interrupted run. The resumed run must reuse it so the
    /// restored records and the newly produced records share one runID (the
    /// artifact validator rejects a mixed-runID generations/candidates/fitness set).
    public let runID: String
    /// First generation to (re)run. Equals `lastCommittedGeneration + 1`.
    public let startGenerationIndex: Int
    /// Population to evaluate at `startGenerationIndex` (produced before the
    /// interruption, stored as the previous checkpoint's `nextPopulation`).
    public let currentPopulation: EvolutionPopulation

    // Accumulated archives restored from generations `0...lastCommittedGeneration`.
    public let generations: [PopulationGenerationRecord]
    public let candidates: [GenomeCandidate]
    public let fitness: [FitnessSummary]
    public let evaluationTraces: [EvolutionCandidateEvaluationTrace]

    // Control state restored from the latest committed generation.
    public let mutationRate: Double
    public let mutationNoiseScale: Double
    public let earlyStopping: EvolutionEarlyStoppingSnapshot
    public let incumbentCandidateID: String?
    public let incumbentFitness: Double?
    public let bestAcceptedFitness: FitnessSummary?

    public init(
        runID: String,
        startGenerationIndex: Int,
        currentPopulation: EvolutionPopulation,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        evaluationTraces: [EvolutionCandidateEvaluationTrace],
        mutationRate: Double,
        mutationNoiseScale: Double,
        earlyStopping: EvolutionEarlyStoppingSnapshot,
        incumbentCandidateID: String?,
        incumbentFitness: Double?,
        bestAcceptedFitness: FitnessSummary?
    ) {
        self.runID = runID
        self.startGenerationIndex = max(0, startGenerationIndex)
        self.currentPopulation = currentPopulation
        self.generations = generations
        self.candidates = candidates
        self.fitness = fitness
        self.evaluationTraces = evaluationTraces
        self.mutationRate = mutationRate
        self.mutationNoiseScale = mutationNoiseScale
        self.earlyStopping = earlyStopping
        self.incumbentCandidateID = incumbentCandidateID
        self.incumbentFitness = incumbentFitness
        self.bestAcceptedFitness = bestAcceptedFitness
    }
}
