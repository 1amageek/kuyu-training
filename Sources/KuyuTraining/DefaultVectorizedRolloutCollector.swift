public struct DefaultVectorizedRolloutCollector<
    Policy: VectorizedPolicyEvaluating,
    World: VectorizedWorldSimulating
>: VectorizedRolloutCollecting where
    Policy.Candidate == World.Candidate,
    Policy.ObservationBatch == World.ObservationBatch,
    Policy.ActionBatch == World.ActionBatch {
    public typealias Candidate = Policy.Candidate

    private let policy: Policy
    private let world: World

    public init(policy: Policy, world: World) {
        self.policy = policy
        self.world = world
    }

    public func collect(
        request: VectorizedRolloutRequest<Candidate>
    ) async throws -> VectorizedRolloutBatchResult {
        var observations = try await world.reset(request: request)
        for _ in 0..<request.batchSpec.rolloutHorizon {
            try Task.checkCancellation()
            let actions = try await policy.evaluateActions(
                candidates: request.candidates,
                observations: observations,
                spec: request.batchSpec
            )
            observations = try await world.step(actions: actions, request: request)
        }
        return try await world.finish(request: request)
    }
}
