import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

/// Acknowledgment written atomically by the trainer as
/// `control/ack-<sequence>.json` when a control command is applied or
/// explicitly rejected.
public struct TrainingRunControlAcknowledgment: Sendable, Codable, Equatable {
    public let sequence: Int
    public let command: String
    public let appliedAt: Date
    /// Iteration boundary at which the command was applied (or rejected).
    public let iteration: Int
    public let rejected: Bool
    /// Mandatory when `rejected == true`.
    public let reason: String?

    public init(
        sequence: Int,
        command: String,
        appliedAt: Date,
        iteration: Int,
        rejected: Bool = false,
        reason: String? = nil
    ) {
        self.sequence = sequence
        self.command = command
        self.appliedAt = appliedAt
        self.iteration = iteration
        self.rejected = rejected
        self.reason = reason
    }
}
