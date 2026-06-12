import Foundation

/// Control request written atomically by clients as `control/command.json`.
///
/// The trainer polls it at iteration boundaries only; commands never preempt
/// a running iteration. `command` is stored as a raw string so an unknown
/// value can be acknowledged as rejected instead of being silently ignored.
public struct TrainingRunControlCommand: Sendable, Codable, Equatable {
    /// Monotonically increasing per run.
    public let sequence: Int
    public let command: String
    public let requestedAt: Date
    /// Client identifier (e.g. `kuyu-cli`, `bounded-ui`).
    public let requestedBy: String

    /// Typed view of `command`; nil for unknown actions.
    public var action: TrainingRunControlAction? {
        TrainingRunControlAction(rawValue: command)
    }

    public init(sequence: Int, action: TrainingRunControlAction, requestedAt: Date, requestedBy: String) {
        self.init(sequence: sequence, command: action.rawValue, requestedAt: requestedAt, requestedBy: requestedBy)
    }

    public init(sequence: Int, command: String, requestedAt: Date, requestedBy: String) {
        self.sequence = sequence
        self.command = command
        self.requestedAt = requestedAt
        self.requestedBy = requestedBy
    }

    private enum CodingKeys: String, CodingKey {
        case sequence
        case command
        case requestedAt
        case requestedBy
    }
}
