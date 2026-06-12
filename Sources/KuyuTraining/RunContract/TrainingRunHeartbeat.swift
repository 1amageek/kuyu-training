import Foundation

/// Liveness beacon, atomically rewritten by the trainer at least once per
/// iteration and at least every `TrainingRunContractSchema.defaultHeartbeatInterval`
/// seconds during long phases.
public struct TrainingRunHeartbeat: Sendable, Codable, Equatable {
    public let updatedAt: Date
    /// Latest started iteration.
    public let iteration: Int
    /// Current phase identifier (e.g. `rollout`, `update`, `evaluation`).
    public let phase: String
    /// Writer process identifier; readers combine it with `outcome.json`
    /// status to distinguish live, finished, and interrupted runs.
    public let processIdentifier: Int32

    public init(updatedAt: Date, iteration: Int, phase: String, processIdentifier: Int32) {
        self.updatedAt = updatedAt
        self.iteration = iteration
        self.phase = phase
        self.processIdentifier = processIdentifier
    }
}
