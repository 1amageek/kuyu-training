import Foundation
import KuyuTrainingContracts

public struct EvolutionSeedRequest: Sendable, Equatable {
    public let config: EvolutionRunConfig
    public let artifactDirectory: URL
    public let mutationRate: Double
    public let mutationNoiseScale: Double
    public let commonRandomSeed: UInt64

    public init(
        config: EvolutionRunConfig,
        artifactDirectory: URL,
        mutationRate: Double? = nil,
        mutationNoiseScale: Double? = nil,
        commonRandomSeed: UInt64? = nil
    ) {
        self.config = config
        self.artifactDirectory = artifactDirectory
        self.mutationRate = mutationRate ?? config.mutationRate
        self.mutationNoiseScale = mutationNoiseScale ?? config.mutationNoiseScale
        self.commonRandomSeed = commonRandomSeed ?? config.commonRandomSeed
    }
}

public struct EvolutionGenerationRequest: Sendable, Equatable {
    public let config: EvolutionRunConfig
    public let previousPopulation: EvolutionPopulation
    public let fitness: [FitnessSummary]
    public let eliteCandidateIDs: [String]
    public let parentCandidateIDs: [String]
    public let mutationRate: Double
    public let mutationNoiseScale: Double
    public let commonRandomSeed: UInt64
    public let generationArtifactDirectory: URL

    public init(
        config: EvolutionRunConfig,
        previousPopulation: EvolutionPopulation,
        fitness: [FitnessSummary],
        eliteCandidateIDs: [String],
        parentCandidateIDs: [String]? = nil,
        mutationRate: Double? = nil,
        mutationNoiseScale: Double? = nil,
        commonRandomSeed: UInt64? = nil,
        generationArtifactDirectory: URL
    ) {
        self.config = config
        self.previousPopulation = previousPopulation
        self.fitness = fitness
        self.eliteCandidateIDs = eliteCandidateIDs
        self.parentCandidateIDs = parentCandidateIDs ?? eliteCandidateIDs
        self.mutationRate = mutationRate ?? config.mutationRate
        self.mutationNoiseScale = mutationNoiseScale ?? config.mutationNoiseScale
        self.commonRandomSeed = commonRandomSeed ?? config.commonRandomSeed
        self.generationArtifactDirectory = generationArtifactDirectory
    }
}

public protocol EvolutionaryTrainingBackend: Sendable {
    func seedPopulation(request: EvolutionSeedRequest) async throws -> EvolutionPopulation
    func produceNextGeneration(request: EvolutionGenerationRequest) async throws -> EvolutionPopulation
}

public struct EvolutionCandidateEvaluationRequest: Sendable, Equatable {
    public let config: EvolutionRunConfig
    public let candidate: GenomeCandidate
    public let generationArtifactDirectory: URL
    public let workerCount: Int

    public init(
        config: EvolutionRunConfig,
        candidate: GenomeCandidate,
        generationArtifactDirectory: URL,
        workerCount: Int
    ) {
        self.config = config
        self.candidate = candidate
        self.generationArtifactDirectory = generationArtifactDirectory
        self.workerCount = max(1, workerCount)
    }
}

public protocol EvolutionCandidateEvaluating: Sendable {
    func evaluateCandidate(request: EvolutionCandidateEvaluationRequest) async throws -> FitnessSummary
}

public struct EvolutionCandidateBatchEvaluationRequest: Sendable, Equatable {
    public let config: EvolutionRunConfig
    public let candidates: [GenomeCandidate]
    public let generationArtifactDirectory: URL
    public let workerCount: Int

    public init(
        config: EvolutionRunConfig,
        candidates: [GenomeCandidate],
        generationArtifactDirectory: URL,
        workerCount: Int
    ) {
        self.config = config
        self.candidates = candidates
        self.generationArtifactDirectory = generationArtifactDirectory
        self.workerCount = max(1, workerCount)
    }
}

public protocol EvolutionCandidateBatchEvaluating: EvolutionCandidateEvaluating {
    func evaluateCandidates(request: EvolutionCandidateBatchEvaluationRequest) async throws -> [FitnessSummary]
}
