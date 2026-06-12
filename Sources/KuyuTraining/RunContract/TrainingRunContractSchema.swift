import Foundation

/// File-layout constants and run-root resolution for the training run contract.
///
/// Normative reference: `kuyu/TRAINING_RUN_CONTRACT.md`. One run is one
/// directory under the run root; every file name below is part of the
/// cross-client contract and must not be renamed casually.
public enum TrainingRunContractSchema {
    /// Current contract schema version stamped into `manifest.json`.
    public static let version = 1

    public static let manifestFileName = "manifest.json"
    public static let journalFileName = "iterations.jsonl"
    public static let heartbeatFileName = "heartbeat.json"
    public static let outcomeFileName = "outcome.json"
    public static let controlDirectoryName = "control"
    public static let controlCommandFileName = "command.json"
    public static let controlAckFilePrefix = "ack-"
    public static let controlAckFileSuffix = ".json"

    /// Environment variable that overrides the default run root.
    public static let runRootEnvironmentKey = "KUYU_RUN_ROOT"

    /// Default heartbeat refresh interval in seconds during long phases.
    public static let defaultHeartbeatInterval: TimeInterval = 30

    /// Resolves the run root directory.
    ///
    /// `KUYU_RUN_ROOT` wins when set and must be an absolute path; otherwise
    /// the durable default `~/.kuyu/runs` is used. Runs are evidence, so the
    /// root is never placed under `/tmp` or a cache directory by default.
    public static func resolveRunRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        if let override = environment[runRootEnvironmentKey] {
            guard override.hasPrefix("/") else {
                throw TrainingRunContractError.invalidRunRoot(
                    path: override,
                    reason: "\(runRootEnvironmentKey) must be an absolute path"
                )
            }
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kuyu", isDirectory: true)
            .appendingPathComponent("runs", isDirectory: true)
    }

    /// File name for the acknowledgment of control command `sequence`.
    public static func controlAckFileName(sequence: Int) -> String {
        "\(controlAckFilePrefix)\(sequence)\(controlAckFileSuffix)"
    }
}
