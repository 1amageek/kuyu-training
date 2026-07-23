import Foundation

/// Writer-side driver that binds a training harness to the durable
/// training-run contract.
///
/// Owns the `TrainingRunArchiveWriter` lifecycle for one logical run: manifest
/// creation, per-iteration journal appends, heartbeats, control-command
/// handling, and terminal outcome writes. The harness keeps its own resume
/// state; this driver guarantees the journal stays gap-free by skipping
/// appends the journal already contains (valid under Tier-0 determinism,
/// where a redone iteration produces an identical record).
public final class TrainingRunDriver {
    /// Late-binding slot so a wrapper can reach the driver created deep
    /// inside a training function when an error propagates out.
    public final class Slot {
        public var driver: TrainingRunDriver?

        public init() {}
    }

    public enum ControlDirective: Sendable, Equatable {
        case continueRun
        case stopRun
    }

    public enum DriverError: Error, CustomStringConvertible {
        case gitCommandFailed(command: String, reason: String)
        case invalidSeedOverride(variable: String, value: String)
        case checkpointDigestFailed(path: String, reason: String)

        public var description: String {
            switch self {
            case .gitCommandFailed(let command, let reason):
                return "git command failed (\(command)): \(reason)"
            case .invalidSeedOverride(let variable, let value):
                return "invalid seed override \(variable)=\(value); expected a UInt64"
            case .checkpointDigestFailed(let path, let reason):
                return "checkpoint digest failed for \(path): \(reason)"
            }
        }
    }

    public enum FinishDisposition: Sendable, Equatable {
        case completed
        case cancelled
        case failed(reason: String)
    }

    var writer: TrainingRunArchiveWriter
    public internal(set) var isFinished = false
    public let runIDString: String

    public var runDirectoryPath: String {
        writer.runDirectory.path
    }

    public var nextJournalIteration: Int {
        writer.nextIteration
    }

    init(writer: TrainingRunArchiveWriter) {
        self.writer = writer
        self.runIDString = writer.runID.rawValue
    }
}
