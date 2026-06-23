import KuyuTrainingContracts
public protocol VectorizedPolicyEvaluating: Sendable {
    associatedtype Candidate: Sendable
    associatedtype ObservationBatch: Sendable
    associatedtype ActionBatch: Sendable

    func evaluateActions(
        candidates: [VectorizedCandidateReference<Candidate>],
        observations: ObservationBatch,
        spec: VectorizedTrainingBatchSpec
    ) async throws -> ActionBatch
}

public protocol VectorizedWorldSimulating: Sendable {
    associatedtype Candidate: Sendable
    associatedtype ObservationBatch: Sendable
    associatedtype ActionBatch: Sendable

    func reset(
        request: VectorizedRolloutRequest<Candidate>
    ) async throws -> ObservationBatch

    func step(
        actions: ActionBatch,
        request: VectorizedRolloutRequest<Candidate>
    ) async throws -> ObservationBatch

    func finish(
        request: VectorizedRolloutRequest<Candidate>
    ) async throws -> VectorizedRolloutBatchResult
}

public protocol VectorizedRolloutCollecting: Sendable {
    associatedtype Candidate: Sendable

    func collect(
        request: VectorizedRolloutRequest<Candidate>
    ) async throws -> VectorizedRolloutBatchResult
}
