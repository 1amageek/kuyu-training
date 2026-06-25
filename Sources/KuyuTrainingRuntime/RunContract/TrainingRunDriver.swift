import CryptoKit
import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

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

    private var writer: TrainingRunArchiveWriter
    public private(set) var isFinished = false
    public let runIDString: String

    public var runDirectoryPath: String {
        writer.runDirectory.path
    }

    public var nextJournalIteration: Int {
        writer.nextIteration
    }

    private init(writer: TrainingRunArchiveWriter) {
        self.writer = writer
        self.runIDString = writer.runID.rawValue
    }

    // MARK: - Lifecycle

    /// Starts a new run directory under `runRoot`.
    ///
    /// `repositoryDirectory` anchors the recorded code identity: `git
    /// rev-parse HEAD` and the dirty check run against the repository that
    /// contains it. Callers pass the directory of the code under training —
    /// a missing or non-git directory is a typed error, never a silent skip.
    public static func begin(
        task: String,
        profile: String,
        semanticVersion: String,
        cacheKey: String,
        mlxGlobalSeed: UInt64,
        noiseSeedSalt: UInt64?,
        determinismTier: Int,
        runRoot: URL,
        repositoryDirectory: URL
    ) throws -> TrainingRunDriver {
        let runID = generateRunID(task: task)
        let code = try resolveCodeIdentity(repositoryDirectory: repositoryDirectory)
        let manifest = TrainingRunManifest(
            runID: TrainingRunID(runID),
            createdAt: Date(),
            task: task,
            profile: profile,
            semanticVersion: semanticVersion,
            cacheKey: cacheKey,
            code: code,
            determinism: TrainingRunManifest.DeterminismStamp(
                mlxGlobalSeed: mlxGlobalSeed,
                noiseSeedSalt: noiseSeedSalt,
                tier: determinismTier
            ),
            host: TrainingRunManifest.HostIdentity(
                hostName: ProcessInfo.processInfo.hostName,
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                processIdentifier: ProcessInfo.processInfo.processIdentifier
            ),
            launch: TrainingRunManifest.LaunchRecord(
                executablePath: CommandLine.arguments.first ?? "unknown",
                arguments: Array(CommandLine.arguments.dropFirst()),
                environmentOverrides: relevantEnvironmentOverrides()
            )
        )
        let writer = try TrainingRunArchiveWriter.create(manifest: manifest, in: runRoot)
        return TrainingRunDriver(writer: writer)
    }

    public static func resume(runID: String, runRoot: URL) throws -> TrainingRunDriver {
        let writer = try TrainingRunArchiveWriter.open(
            runID: TrainingRunID(runID),
            in: runRoot,
            repairingTornTail: true
        )
        if let repaired = writer.repairedTailByteCount, repaired > 0 {
            print("TRAINING-RUN resume repaired torn journal tail (\(repaired) bytes) run=\(runID)")
        }
        return TrainingRunDriver(writer: writer)
    }

    // MARK: - Journal

    /// Appends an iteration record, skipping records the journal already
    /// holds (crash-window redo under Tier-0 determinism reproduces them
    /// bit-identically, so skipping is sound).
    public func recordIteration(_ record: TrainingRunIterationRecord) throws {
        if record.iteration < writer.nextIteration {
            print("TRAINING-RUN journal already contains iteration \(record.iteration) (skip)")
            return
        }
        try writer.appendIteration(record)
    }

    public func writeHeartbeat(iteration: Int, phase: String) throws {
        try writer.writeHeartbeat(
            TrainingRunHeartbeat(
                updatedAt: Date(),
                iteration: iteration,
                phase: phase,
                processIdentifier: ProcessInfo.processInfo.processIdentifier
            )
        )
    }

    // MARK: - Control

    /// Polls `control/command.json` and applies the pending command, if any.
    /// `pause` blocks here (heartbeating) until a `resume` or `stop` arrives.
    ///
    /// Runs on the caller's actor (`nonisolated(nonsending)`) so the
    /// non-`Sendable` driver never crosses an isolation boundary.
    nonisolated(nonsending) public func applyPendingControl(iteration: Int) async throws -> ControlDirective {
        while true {
            guard let command = try writer.pendingControlCommand() else {
                return .continueRun
            }
            switch command.action {
            case .stop:
                try writer.acknowledgeControlCommand(
                    TrainingRunControlAcknowledgment(
                        sequence: command.sequence,
                        command: command.command,
                        appliedAt: Date(),
                        iteration: iteration
                    )
                )
                return .stopRun
            case .pause:
                try writer.acknowledgeControlCommand(
                    TrainingRunControlAcknowledgment(
                        sequence: command.sequence,
                        command: command.command,
                        appliedAt: Date(),
                        iteration: iteration
                    )
                )
                try writer.writeOutcome(
                    TrainingRunOutcome(status: .paused, updatedAt: Date())
                )
                print("TRAINING-RUN paused at iteration \(iteration) (awaiting resume)")
                try await waitWhilePaused(iteration: iteration)
                try writer.writeOutcome(
                    TrainingRunOutcome(status: .running, updatedAt: Date())
                )
                print("TRAINING-RUN resumed at iteration \(iteration)")
                continue
            case .resume:
                try writer.acknowledgeControlCommand(
                    TrainingRunControlAcknowledgment(
                        sequence: command.sequence,
                        command: command.command,
                        appliedAt: Date(),
                        iteration: iteration,
                        rejected: true,
                        reason: "run is not paused"
                    )
                )
                continue
            case .checkpoint:
                try writer.acknowledgeControlCommand(
                    TrainingRunControlAcknowledgment(
                        sequence: command.sequence,
                        command: command.command,
                        appliedAt: Date(),
                        iteration: iteration,
                        rejected: true,
                        reason: "checkpoint-on-demand is not supported by this harness"
                    )
                )
                continue
            case nil:
                try writer.acknowledgeControlCommand(
                    TrainingRunControlAcknowledgment(
                        sequence: command.sequence,
                        command: command.command,
                        appliedAt: Date(),
                        iteration: iteration,
                        rejected: true,
                        reason: "unknown command: \(command.command)"
                    )
                )
                continue
            }
        }
    }

    nonisolated(nonsending) private func waitWhilePaused(iteration: Int) async throws {
        while true {
            try await Task.sleep(for: .seconds(2))
            try writeHeartbeat(iteration: iteration, phase: "paused")
            guard let command = try writer.pendingControlCommand() else {
                continue
            }
            switch command.action {
            case .resume:
                try writer.acknowledgeControlCommand(
                    TrainingRunControlAcknowledgment(
                        sequence: command.sequence,
                        command: command.command,
                        appliedAt: Date(),
                        iteration: iteration
                    )
                )
                return
            case .stop:
                // Leave the stop pending; the outer loop consumes it and
                // returns .stopRun so the harness exits cleanly.
                return
            default:
                try writer.acknowledgeControlCommand(
                    TrainingRunControlAcknowledgment(
                        sequence: command.sequence,
                        command: command.command,
                        appliedAt: Date(),
                        iteration: iteration,
                        rejected: true,
                        reason: "command not applicable while paused: \(command.command)"
                    )
                )
                continue
            }
        }
    }

    // MARK: - Outcomes

    @discardableResult
    public func finish(result: TrainingRunResult) throws -> FinishDisposition {
        let classification = TrainingRunResultTerminalClassifier().classify(result: result)
        switch classification.status {
        case .accepted:
            try finishCompleted(acceptedCheckpointPath: classification.acceptedCheckpointPath)
            return .completed
        case .rejected:
            try finishCompleted(acceptedCheckpointPath: nil)
            return .completed
        case .cancelled:
            try finishCancelled(acceptedCheckpointPath: nil)
            return .cancelled
        case .failed, .incomplete:
            finishFailedReportingSecondaryFailure(reason: classification.reason)
            return .failed(reason: classification.reason)
        }
    }

    public func finishCompleted(acceptedCheckpointPath: String?) throws {
        try finish(status: .completed, acceptedCheckpointPath: acceptedCheckpointPath, failureReason: nil)
    }

    public func finishCancelled(acceptedCheckpointPath: String?) throws {
        try finish(status: .cancelled, acceptedCheckpointPath: acceptedCheckpointPath, failureReason: nil)
    }

    /// Best-effort failure outcome for error-propagation paths. Never throws:
    /// the original training error must surface, not be masked by a secondary
    /// journaling failure — which is reported explicitly instead.
    public func finishFailedReportingSecondaryFailure(reason: String) {
        do {
            try finish(status: .failed, acceptedCheckpointPath: nil, failureReason: reason)
        } catch {
            print("TRAINING-RUN WARNING: failed to write failure outcome for run=\(runIDString): \(error)")
        }
    }

    private func finish(
        status: TrainingRunLifecycleStatus,
        acceptedCheckpointPath: String?,
        failureReason: String?
    ) throws {
        guard !isFinished else { return }
        let finalIteration = writer.nextIteration > 0 ? writer.nextIteration - 1 : nil
        try writer.writeOutcome(
            TrainingRunOutcome(
                status: status,
                updatedAt: Date(),
                finalIteration: finalIteration,
                failureReason: failureReason,
                acceptedCheckpointPath: acceptedCheckpointPath
            )
        )
        isFinished = true
    }

    // MARK: - Checkpoint digest

    /// Computes a stable SHA-256 digest over a checkpoint directory: regular
    /// files sorted by relative path, hashing `path\0content\0` per file.
    public func checkpointReference(for checkpointURL: URL) throws -> TrainingRunIterationRecord.CheckpointReference {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: checkpointURL.path, isDirectory: &isDirectory) else {
            throw DriverError.checkpointDigestFailed(
                path: checkpointURL.path,
                reason: "checkpoint path does not exist"
            )
        }
        var hasher = SHA256()
        if isDirectory.boolValue {
            guard let enumerator = fm.enumerator(
                at: checkpointURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                throw DriverError.checkpointDigestFailed(
                    path: checkpointURL.path,
                    reason: "could not enumerate checkpoint directory"
                )
            }
            var files: [(relativePath: String, url: URL)] = []
            for case let fileURL as URL in enumerator {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                let relative = fileURL.path.replacingOccurrences(
                    of: checkpointURL.path + "/",
                    with: ""
                )
                files.append((relative, fileURL))
            }
            files.sort { $0.relativePath < $1.relativePath }
            for file in files {
                let content = try Data(contentsOf: file.url)
                hasher.update(data: Data(file.relativePath.utf8))
                hasher.update(data: Data([0]))
                hasher.update(data: content)
                hasher.update(data: Data([0]))
            }
        } else {
            let content = try Data(contentsOf: checkpointURL)
            hasher.update(data: Data(checkpointURL.lastPathComponent.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: content)
            hasher.update(data: Data([0]))
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return TrainingRunIterationRecord.CheckpointReference(
            path: checkpointURL.path,
            sha256Digest: digest
        )
    }

    // MARK: - Seed resolution

    /// Resolves the MLX global seed from `KUYU_MLX_SEED`, defaulting to 0.
    /// An unparsable value is a typed error — never silently fall back.
    public static func resolveMLXGlobalSeed(environment: [String: String]) throws -> UInt64 {
        guard let raw = environment["KUYU_MLX_SEED"] else {
            return 0
        }
        guard let seed = UInt64(raw) else {
            throw DriverError.invalidSeedOverride(variable: "KUYU_MLX_SEED", value: raw)
        }
        return seed
    }

    // MARK: - Identity helpers

    private static func generateRunID(task: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: Date())
        let alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
        let suffix = String((0..<4).map { _ in alphabet.randomElement() ?? "0" })
        return "\(task)-\(stamp)-\(suffix)"
    }

    private static func resolveCodeIdentity(repositoryDirectory: URL) throws -> TrainingRunManifest.CodeIdentity {
        let head = try runGitCommand(
            arguments: ["-C", repositoryDirectory.path, "rev-parse", "HEAD"]
        )
        let status = try runGitCommand(
            arguments: ["-C", repositoryDirectory.path, "status", "--porcelain"]
        )
        #if DEBUG
        let buildConfiguration = "debug"
        #else
        let buildConfiguration = "release"
        #endif
        return TrainingRunManifest.CodeIdentity(
            gitHead: head,
            gitDirty: !status.isEmpty,
            buildConfiguration: buildConfiguration
        )
    }

    private static func runGitCommand(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw DriverError.gitCommandFailed(
                command: "git " + arguments.joined(separator: " "),
                reason: String(describing: error)
            )
        }
        process.waitUntilExit()
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "unknown git error"
            throw DriverError.gitCommandFailed(
                command: "git " + arguments.joined(separator: " "),
                reason: message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let output = String(data: outputData, encoding: .utf8) ?? ""
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func relevantEnvironmentOverrides() -> [String: String] {
        ProcessInfo.processInfo.environment.filter { key, _ in
            key.hasPrefix("KUYU_") || key.hasPrefix("MANAS_")
        }
    }
}
