public protocol TypedTrainingBackend: Sendable {
    associatedtype Genome: Sendable
    associatedtype Candidate: Sendable
    associatedtype Checkpoint: Sendable
    associatedtype Observation: Sendable
    associatedtype Action: Sendable
    associatedtype Fitness: Comparable & Sendable

    func loadCheckpoint(_ reference: ModelBundleReference) async throws -> Checkpoint
    func seedPopulation(from checkpoint: Checkpoint, request: PopulationSeedRequest) async throws -> [Candidate]
    func evaluate(
        _ candidate: Candidate,
        in context: TrainingEvaluationContext<Observation, Action>
    ) async throws -> CandidateEvaluation<Candidate, Fitness>
    func reproduce(_ request: ReproductionRequest<Candidate>) async throws -> [Candidate]
    func publish(_ candidate: Candidate, request: CheckpointPublicationRequest) async throws -> Checkpoint
}
