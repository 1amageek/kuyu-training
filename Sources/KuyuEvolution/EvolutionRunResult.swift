import Foundation
import KuyuTrainingContracts

public struct EvolutionRunResult: Sendable, Equatable {
    public let manifest: EvolutionRunManifest
    public let generations: [PopulationGenerationRecord]
    public let candidates: [GenomeCandidate]
    public let fitness: [FitnessSummary]
    public let eliteArchive: EvolutionEliteArchive
    public let qualityDiversityArchive: EvolutionQualityDiversityArchive
    public let lineage: [EvolutionLineageRecord]
    public let evaluationTraces: [EvolutionCandidateEvaluationTrace]
    public let acceptanceEvaluations: [EvolutionCandidateAcceptanceRecord]

    public init(
        manifest: EvolutionRunManifest,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        eliteArchive: EvolutionEliteArchive,
        qualityDiversityArchive: EvolutionQualityDiversityArchive,
        lineage: [EvolutionLineageRecord],
        evaluationTraces: [EvolutionCandidateEvaluationTrace] = [],
        acceptanceEvaluations: [EvolutionCandidateAcceptanceRecord] = []
    ) {
        self.manifest = manifest
        self.generations = generations
        self.candidates = candidates
        self.fitness = fitness
        self.eliteArchive = eliteArchive
        self.qualityDiversityArchive = qualityDiversityArchive
        self.lineage = lineage
        self.evaluationTraces = evaluationTraces
        self.acceptanceEvaluations = acceptanceEvaluations
    }
}
