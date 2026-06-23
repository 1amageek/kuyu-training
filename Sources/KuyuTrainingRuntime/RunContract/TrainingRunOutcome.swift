import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

/// Lifecycle record stored as `outcome.json`, atomically rewritten on every
/// transition.
public struct TrainingRunOutcome: Sendable, Codable, Equatable {
    public let status: TrainingRunLifecycleStatus
    public let updatedAt: Date
    /// Last completed iteration, when any iteration completed.
    public let finalIteration: Int?
    /// Mandatory when `status == .failed`.
    public let failureReason: String?
    /// Final accepted checkpoint, when any.
    public let acceptedCheckpointPath: String?

    public init(
        status: TrainingRunLifecycleStatus,
        updatedAt: Date,
        finalIteration: Int? = nil,
        failureReason: String? = nil,
        acceptedCheckpointPath: String? = nil
    ) {
        self.status = status
        self.updatedAt = updatedAt
        self.finalIteration = finalIteration
        self.failureReason = failureReason
        self.acceptedCheckpointPath = acceptedCheckpointPath
    }

    /// Validates structural invariants before the outcome is persisted.
    public func validate() throws {
        if status == .failed {
            guard let failureReason, !failureReason.isEmpty else {
                throw TrainingRunContractError.invalidOutcome(
                    reason: "status=failed requires a non-empty failureReason"
                )
            }
        }
    }
}
