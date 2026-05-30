import Foundation

/// Durable, self-describing snapshot written at the end of every completed
/// generation `N` (after the next population is produced). Holding only the
/// non-cumulative slice for generation `N` plus the control state needed to run
/// generation `N+1`, the full run state is reconstructed by accumulating the
/// checkpoints of generations `0...N`.
///
/// The generation's RNG is re-derived from its index
/// (`commonRandomSeed(config, generationIndex)`), so no PRNG state is stored:
/// restoring the control state and re-entering the loop at `N+1` reproduces the
/// uninterrupted run bit-for-bit.
public struct EvolutionGenerationCheckpoint: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let runID: String
    /// Plan/config identity. A resume into a checkpoint written under a different
    /// `configHash` is rejected (fail-closed) unless explicitly overridden.
    public let configHash: String
    /// The last fully evaluated and committed generation index. The next
    /// generation to run is `lastCommittedGeneration + 1`.
    public let lastCommittedGeneration: Int

    // Non-cumulative slice for `lastCommittedGeneration`.
    public let generationRecord: PopulationGenerationRecord
    public let generationCandidates: [GenomeCandidate]
    public let generationFitness: [FitnessSummary]
    public let generationTraces: [EvolutionCandidateEvaluationTrace]

    // Control state required to run the next generation.
    public let nextPopulation: EvolutionPopulation
    public let mutationRate: Double
    public let mutationNoiseScale: Double
    public let earlyStopping: EvolutionEarlyStoppingSnapshot
    public let incumbentCandidateID: String?
    public let incumbentFitness: Double?
    public let bestAcceptedFitness: FitnessSummary?

    public init(
        runID: String,
        configHash: String,
        lastCommittedGeneration: Int,
        generationRecord: PopulationGenerationRecord,
        generationCandidates: [GenomeCandidate],
        generationFitness: [FitnessSummary],
        generationTraces: [EvolutionCandidateEvaluationTrace],
        nextPopulation: EvolutionPopulation,
        mutationRate: Double,
        mutationNoiseScale: Double,
        earlyStopping: EvolutionEarlyStoppingSnapshot,
        incumbentCandidateID: String?,
        incumbentFitness: Double?,
        bestAcceptedFitness: FitnessSummary?
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.configHash = configHash
        self.lastCommittedGeneration = max(0, lastCommittedGeneration)
        self.generationRecord = generationRecord
        self.generationCandidates = generationCandidates
        self.generationFitness = generationFitness
        self.generationTraces = generationTraces
        self.nextPopulation = nextPopulation
        self.mutationRate = mutationRate
        self.mutationNoiseScale = mutationNoiseScale
        self.earlyStopping = earlyStopping
        self.incumbentCandidateID = incumbentCandidateID
        self.incumbentFitness = incumbentFitness
        self.bestAcceptedFitness = bestAcceptedFitness
    }
}
