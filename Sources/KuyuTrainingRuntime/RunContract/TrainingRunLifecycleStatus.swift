import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation
/// Lifecycle status recorded in `outcome.json`.
///
/// Truncation (a dead writer that never recorded a terminal status) is not a
/// stored status: it is derived by readers as `status == .running` with a dead
/// writer process. Storing it would race with the dying process; deriving it
/// cannot.
public enum TrainingRunLifecycleStatus: String, Sendable, Codable, Equatable, CaseIterable {
    case running
    case paused
    case completed
    case failed
    case cancelled

    /// Terminal statuses never transition again.
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .running, .paused:
            return false
        }
    }
}
