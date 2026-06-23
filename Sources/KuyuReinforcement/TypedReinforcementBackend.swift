import KuyuTrainingContracts
public protocol TypedReinforcementBackend: Sendable {
    associatedtype Observation: Sendable
    associatedtype Action: Sendable
    associatedtype Policy: Sendable
    associatedtype Checkpoint: Sendable

    func fineTune(
        policy: Policy,
        buffer: RolloutBuffer<Observation, Action>,
        request: ReinforcementTrainingRequest
    ) async throws -> ReinforcementTrainingResult<Checkpoint>
}
