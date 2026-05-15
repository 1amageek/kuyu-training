import Foundation

public struct EvolutionTypedBackendAdapter: TypedTrainingBackend {
    public typealias Genome = GenomeCandidate
    public typealias Candidate = GenomeCandidate
    public typealias Checkpoint = ModelBundleReference
    public typealias Observation = TrainingNoObservation
    public typealias Action = TrainingNoAction
    public typealias Fitness = Double

    public enum AdapterError: Error, Sendable, Equatable {
        case emptyPopulation
        case missingCandidateCheckpoint(String)
    }

    private let config: EvolutionRunConfig
    private let backend: any EvolutionaryTrainingBackend
    private let evaluator: any EvolutionCandidateEvaluating

    public init(
        config: EvolutionRunConfig,
        backend: any EvolutionaryTrainingBackend,
        evaluator: any EvolutionCandidateEvaluating
    ) {
        self.config = config
        self.backend = backend
        self.evaluator = evaluator
    }

    public func loadCheckpoint(_ reference: ModelBundleReference) async throws -> ModelBundleReference {
        reference
    }

    public func seedPopulation(
        from checkpoint: ModelBundleReference,
        request: PopulationSeedRequest
    ) async throws -> [GenomeCandidate] {
        let population = try await backend.seedPopulation(request: EvolutionSeedRequest(
            config: config,
            artifactDirectory: request.artifactRoot,
            mutationRate: config.mutationRate,
            mutationNoiseScale: config.mutationNoiseScale,
            commonRandomSeed: request.seed
        ))
        guard !population.candidates.isEmpty else {
            throw AdapterError.emptyPopulation
        }
        return population.candidates
    }

    public func evaluate(
        _ candidate: GenomeCandidate,
        in context: TrainingEvaluationContext<TrainingNoObservation, TrainingNoAction>
    ) async throws -> CandidateEvaluation<GenomeCandidate, Double> {
        let generationDirectory = context.artifactRoot
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent("generation-\(candidate.generationIndex)", isDirectory: true)
        let summary = try await evaluator.evaluateCandidate(request: EvolutionCandidateEvaluationRequest(
            config: config,
            candidate: candidate,
            generationArtifactDirectory: generationDirectory,
            workerCount: context.workerCount
        ))
        return CandidateEvaluation(
            candidate: candidate,
            candidateID: summary.candidateID,
            fitness: summary.scalarFitness,
            rewardAverage: summary.rewardAverage,
            taskPassRate: summary.taskPassRate,
            holdTimeRatio: summary.holdTimeRatio,
            altitudeErrorRatio: summary.altitudeErrorRatio,
            safetyRate: 1 - summary.safetyViolationRate,
            failureReasons: summary.failureReasons,
            artifactRoot: generationDirectory
        )
    }

    public func reproduce(_ request: ReproductionRequest<GenomeCandidate>) async throws -> [GenomeCandidate] {
        let previousPopulation = EvolutionPopulation(
            runID: request.runID,
            generationIndex: max(0, request.generation - 1),
            candidates: request.parents
        )
        let parentIDs = request.parents.map(\.candidateID)
        let nextPopulation = try await backend.produceNextGeneration(request: EvolutionGenerationRequest(
            config: config,
            previousPopulation: previousPopulation,
            fitness: [],
            eliteCandidateIDs: parentIDs,
            parentCandidateIDs: parentIDs,
            mutationRate: request.mutationRate,
            mutationNoiseScale: request.mutationNoiseScale,
            commonRandomSeed: request.seed,
            generationArtifactDirectory: request.artifactRoot
        ))
        return nextPopulation.candidates
    }

    public func publish(
        _ candidate: GenomeCandidate,
        request: CheckpointPublicationRequest
    ) async throws -> ModelBundleReference {
        guard let checkpointURL = candidate.checkpointURL else {
            throw AdapterError.missingCandidateCheckpoint(candidate.candidateID)
        }
        return ModelBundleReference(
            bundleID: request.destination.bundleID,
            kind: request.destination.kind,
            url: checkpointURL,
            contentHash: request.destination.contentHash,
            descriptorID: request.destination.descriptorID,
            observationSchemaID: request.destination.observationSchemaID,
            actionSchemaID: request.destination.actionSchemaID
        )
    }
}
