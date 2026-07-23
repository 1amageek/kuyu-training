import Foundation
import KuyuTrainingContracts

public struct EvolutionRunArtifactBundle: Sendable, Equatable {
    public let artifactDirectory: URL
    public let contract: EvolutionRunArtifactContract
    public let manifest: EvolutionRunManifest
    public let generations: [PopulationGenerationRecord]
    public let candidates: [GenomeCandidate]
    public let fitness: [FitnessSummary]
    public let eliteArchive: EvolutionEliteArchive
    public let acceptedCheckpoint: EvolutionAcceptedCheckpointDecision
    public let qualityDiversityArchive: EvolutionQualityDiversityArchive
    public let lineage: [EvolutionLineageRecord]
    public let evaluationTraces: [EvolutionCandidateEvaluationTrace]
    public let acceptanceEvaluations: [EvolutionCandidateAcceptanceRecord]

    public init(
        artifactDirectory: URL,
        contract: EvolutionRunArtifactContract,
        manifest: EvolutionRunManifest,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        eliteArchive: EvolutionEliteArchive,
        acceptedCheckpoint: EvolutionAcceptedCheckpointDecision,
        qualityDiversityArchive: EvolutionQualityDiversityArchive,
        lineage: [EvolutionLineageRecord],
        evaluationTraces: [EvolutionCandidateEvaluationTrace],
        acceptanceEvaluations: [EvolutionCandidateAcceptanceRecord]
    ) {
        self.artifactDirectory = artifactDirectory
        self.contract = contract
        self.manifest = manifest
        self.generations = generations
        self.candidates = candidates
        self.fitness = fitness
        self.eliteArchive = eliteArchive
        self.acceptedCheckpoint = acceptedCheckpoint
        self.qualityDiversityArchive = qualityDiversityArchive
        self.lineage = lineage
        self.evaluationTraces = evaluationTraces
        self.acceptanceEvaluations = acceptanceEvaluations
    }

    public var bestFitnessSummary: FitnessSummary? {
        guard let candidateID = eliteArchive.bestCandidateID else { return nil }
        return fullScenarioFitness.first { $0.candidateID == candidateID }
    }

    public var fullScenarioFitness: [FitnessSummary] {
        fitness.filter { $0.evaluationFidelity.isFullScenario }
    }
}
