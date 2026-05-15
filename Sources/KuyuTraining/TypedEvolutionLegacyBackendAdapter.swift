import Foundation

public struct TypedEvolutionLegacyBackendAdapter<Backend: TypedTrainingBackend>: EvolutionaryTrainingBackend
where
    Backend.Candidate == GenomeCandidate,
    Backend.Checkpoint == ModelBundleReference,
    Backend.Observation == TrainingNoObservation,
    Backend.Action == TrainingNoAction,
    Backend.Fitness == Double
{
    private let backend: Backend
    private let checkpoint: ModelBundleReference

    public init(backend: Backend, checkpoint: ModelBundleReference) {
        self.backend = backend
        self.checkpoint = checkpoint
    }

    public func seedPopulation(request: EvolutionSeedRequest) async throws -> EvolutionPopulation {
        let loadedCheckpoint = try await backend.loadCheckpoint(checkpoint)
        let candidates = try await backend.seedPopulation(
            from: loadedCheckpoint,
            request: PopulationSeedRequest(
                runID: request.config.runID,
                populationSize: request.config.populationSize,
                seed: request.commonRandomSeed,
                artifactRoot: request.artifactDirectory,
                preservesIncumbent: true
            )
        )
        return EvolutionPopulation(
            runID: request.config.runID,
            generationIndex: 0,
            candidates: candidates
        )
    }

    public func produceNextGeneration(request: EvolutionGenerationRequest) async throws -> EvolutionPopulation {
        let parentIDs = Set(request.parentCandidateIDs)
        let parents = request.previousPopulation.candidates.filter { parentIDs.contains($0.candidateID) }
        let candidates = try await backend.reproduce(ReproductionRequest(
            runID: request.config.runID,
            generation: request.previousPopulation.generationIndex + 1,
            parents: parents.isEmpty ? request.previousPopulation.candidates : parents,
            targetPopulationSize: request.config.populationSize,
            mutationRate: request.mutationRate,
            mutationNoiseScale: request.mutationNoiseScale,
            seed: request.commonRandomSeed,
            artifactRoot: request.generationArtifactDirectory
        ))
        return EvolutionPopulation(
            runID: request.config.runID,
            generationIndex: request.previousPopulation.generationIndex + 1,
            candidates: candidates
        )
    }
}
