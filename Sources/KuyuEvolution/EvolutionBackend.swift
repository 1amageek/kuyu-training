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
    public let parentCandidates: [GenomeCandidate]
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
        parentCandidates: [GenomeCandidate]? = nil,
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
        self.parentCandidates = parentCandidates ?? previousPopulation.candidates
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
    public enum ValidationError: Error, Sendable, Equatable {
        case invalidBatchIndex(index: Int, count: Int)
        case invalidPopulationSize(population: Int, batch: Int)
    }

    public let config: EvolutionRunConfig
    public let candidates: [GenomeCandidate]
    public let generationArtifactDirectory: URL
    public let workerCount: Int
    public let batchIndex: Int
    public let batchCount: Int
    public let populationSize: Int
    public let workPhase: TrainingWorkPhase

    public init(
        config: EvolutionRunConfig,
        candidates: [GenomeCandidate],
        generationArtifactDirectory: URL,
        workerCount: Int,
        batchIndex: Int = 0,
        batchCount: Int = 1,
        populationSize: Int? = nil,
        workPhase: TrainingWorkPhase = .rollout
    ) throws(ValidationError) {
        guard batchCount > 0, batchIndex >= 0, batchIndex < batchCount else {
            throw ValidationError.invalidBatchIndex(index: batchIndex, count: batchCount)
        }
        let resolvedPopulationSize = populationSize ?? candidates.count
        guard resolvedPopulationSize >= candidates.count, resolvedPopulationSize > 0 else {
            throw ValidationError.invalidPopulationSize(
                population: resolvedPopulationSize,
                batch: candidates.count
            )
        }
        self.config = config
        self.candidates = candidates
        self.generationArtifactDirectory = generationArtifactDirectory
        self.workerCount = max(1, workerCount)
        self.batchIndex = batchIndex
        self.batchCount = batchCount
        self.populationSize = resolvedPopulationSize
        self.workPhase = workPhase
    }

    public var batchID: String {
        let generationIndex = candidates.first?.generationIndex ?? 0
        return "\(config.runID)/g\(generationIndex)/\(workPhase.rawValue)/batch-\(batchIndex)-of-\(batchCount)"
    }
}

public protocol EvolutionCandidateBatchEvaluating: EvolutionCandidateEvaluating {
    func evaluateCandidates(request: EvolutionCandidateBatchEvaluationRequest) async throws -> [FitnessSummary]
    func evaluateCandidates(
        request: EvolutionCandidateBatchEvaluationRequest,
        progressReporter: (any TrainingProgressReporting)?
    ) async throws -> [FitnessSummary]
}

public protocol EvolutionPopulationBatchEvaluating: EvolutionCandidateBatchEvaluating {}

public extension EvolutionCandidateBatchEvaluating {
    func evaluateCandidates(
        request: EvolutionCandidateBatchEvaluationRequest,
        progressReporter: (any TrainingProgressReporting)?
    ) async throws -> [FitnessSummary] {
        _ = progressReporter
        return try await evaluateCandidates(request: request)
    }
}
