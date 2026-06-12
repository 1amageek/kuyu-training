import Darwin
import Foundation

/// Single-writer side of a training run directory.
///
/// Exactly one process may write a run directory. Directory creation is the
/// lock acquisition: `create(manifest:in:)` fails on an existing directory,
/// and `open(runID:in:repairingTornTail:)` refuses to attach while the
/// previous writer is still alive.
///
/// Write disciplines (normative, see `kuyu/TRAINING_RUN_CONTRACT.md`):
/// - `manifest.json` is written once and never modified.
/// - `iterations.jsonl` is append-only; one record = one `write(2)` call of a
///   single newline-terminated JSON line.
/// - `heartbeat.json` and `outcome.json` are atomically rewritten.
public struct TrainingRunArchiveWriter: Sendable {
    public let runDirectory: URL
    public let runID: TrainingRunID
    /// Iteration index the next `appendIteration(_:)` must carry.
    public private(set) var nextIteration: Int
    /// Byte count trimmed from a torn journal tail during `open`, when tail
    /// repair was explicitly requested; nil otherwise.
    public let repairedTailByteCount: Int?

    private init(
        runDirectory: URL,
        runID: TrainingRunID,
        nextIteration: Int,
        repairedTailByteCount: Int?
    ) {
        self.runDirectory = runDirectory
        self.runID = runID
        self.nextIteration = nextIteration
        self.repairedTailByteCount = repairedTailByteCount
    }

    // MARK: - Creation

    /// Creates the run directory, writes the manifest, an empty journal, the
    /// initial `running` outcome, and the control directory.
    ///
    /// Creating a run whose directory already exists is an error; writers
    /// never reuse or repair an existing directory.
    public static func create(
        manifest: TrainingRunManifest,
        in runRoot: URL
    ) throws -> TrainingRunArchiveWriter {
        try manifest.validate()
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: runRoot, withIntermediateDirectories: true)
        } catch {
            throw TrainingRunContractError.invalidRunRoot(
                path: runRoot.path,
                reason: String(describing: error)
            )
        }
        let runDirectory = runRoot.appendingPathComponent(manifest.runID.rawValue, isDirectory: true)
        do {
            try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: false)
        } catch {
            if fileManager.fileExists(atPath: runDirectory.path) {
                throw TrainingRunContractError.duplicateRunDirectory(path: runDirectory.path)
            }
            throw TrainingRunContractError.writeFailed(
                path: runDirectory.path,
                reason: String(describing: error)
            )
        }
        let controlDirectory = runDirectory.appendingPathComponent(
            TrainingRunContractSchema.controlDirectoryName,
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(at: controlDirectory, withIntermediateDirectories: false)
        } catch {
            throw TrainingRunContractError.writeFailed(
                path: controlDirectory.path,
                reason: String(describing: error)
            )
        }
        let writer = TrainingRunArchiveWriter(
            runDirectory: runDirectory,
            runID: manifest.runID,
            nextIteration: 0,
            repairedTailByteCount: nil
        )
        try writer.writeDocument(manifest, to: writer.manifestURL)
        do {
            try Data().write(to: writer.journalURL, options: [.atomic])
        } catch {
            throw TrainingRunContractError.writeFailed(
                path: writer.journalURL.path,
                reason: String(describing: error)
            )
        }
        try writer.writeOutcome(
            TrainingRunOutcome(status: .running, updatedAt: manifest.createdAt)
        )
        return writer
    }

    // MARK: - Resume

    /// Attaches to an existing run directory for resume.
    ///
    /// Refuses when the previous writer is recorded as non-terminal and its
    /// process is still alive (single-writer rule; the current process may
    /// always reattach to its own run). A torn journal tail blocks resume
    /// unless `repairingTornTail` is explicitly true, in which case exactly
    /// the torn bytes are trimmed and reported via `repairedTailByteCount`.
    public static func open(
        runID: TrainingRunID,
        in runRoot: URL,
        repairingTornTail: Bool = false
    ) throws -> TrainingRunArchiveWriter {
        let runDirectory = runRoot.appendingPathComponent(runID.rawValue, isDirectory: true)
        let reader = TrainingRunArchiveReader(runDirectory: runDirectory)
        let manifest = try reader.loadManifest()
        let outcome = try reader.loadOutcome()
        if !outcome.status.isTerminal {
            let heartbeat = try reader.loadHeartbeat()
            let previousWriter = heartbeat?.processIdentifier ?? manifest.host.processIdentifier
            let currentProcess = ProcessInfo.processInfo.processIdentifier
            if previousWriter != currentProcess,
               TrainingRunArchiveReader.isProcessAlive(previousWriter) {
                throw TrainingRunContractError.runStillLive(processIdentifier: previousWriter)
            }
        }
        var repairedTailByteCount: Int?
        var journal = try reader.readJournal()
        if journal.truncatedTailBytes > 0 {
            guard repairingTornTail else {
                throw TrainingRunContractError.tornJournalTail(
                    byteCount: journal.truncatedTailBytes,
                    runID: runID.rawValue
                )
            }
            let journalURL = runDirectory.appendingPathComponent(
                TrainingRunContractSchema.journalFileName,
                isDirectory: false
            )
            try trimTail(byteCount: journal.truncatedTailBytes, journalURL: journalURL)
            repairedTailByteCount = journal.truncatedTailBytes
            journal = try reader.readJournal()
            guard journal.truncatedTailBytes == 0 else {
                throw TrainingRunContractError.corruptedFile(
                    name: TrainingRunContractSchema.journalFileName,
                    runID: runID.rawValue,
                    reason: "torn tail persisted after repair"
                )
            }
        }
        let nextIteration = journal.records.last.map { $0.iteration + 1 } ?? 0
        return TrainingRunArchiveWriter(
            runDirectory: runDirectory,
            runID: runID,
            nextIteration: nextIteration,
            repairedTailByteCount: repairedTailByteCount
        )
    }

    // MARK: - Journal

    /// Appends one iteration record as a single newline-terminated JSON line
    /// using one `write(2)` call. Iterations must be appended in strict order
    /// with no gaps.
    public mutating func appendIteration(_ record: TrainingRunIterationRecord) throws {
        guard record.iteration == nextIteration else {
            throw TrainingRunContractError.nonMonotonicIteration(
                expected: nextIteration,
                found: record.iteration
            )
        }
        var data: Data
        do {
            data = try TrainingRunContractCodec.makeJournalEncoder().encode(record)
        } catch {
            throw TrainingRunContractError.writeFailed(
                path: journalURL.path,
                reason: "encode: \(String(describing: error))"
            )
        }
        guard !data.contains(0x0A) else {
            throw TrainingRunContractError.writeFailed(
                path: journalURL.path,
                reason: "encoded record contains a newline"
            )
        }
        data.append(0x0A)
        try appendDatum(data, to: journalURL)
        nextIteration += 1
    }

    // MARK: - Heartbeat / outcome

    public func writeHeartbeat(_ heartbeat: TrainingRunHeartbeat) throws {
        try writeDocument(heartbeat, to: heartbeatURL)
    }

    public func writeOutcome(_ outcome: TrainingRunOutcome) throws {
        try outcome.validate()
        try writeDocument(outcome, to: outcomeURL)
    }

    // MARK: - Control (trainer side)

    /// Pending control command, decoded for application at the next iteration
    /// boundary; nil when no command is pending.
    public func pendingControlCommand() throws -> TrainingRunControlCommand? {
        guard FileManager.default.fileExists(atPath: controlCommandURL.path) else {
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: controlCommandURL)
        } catch {
            throw TrainingRunContractError.corruptedFile(
                name: TrainingRunContractSchema.controlCommandFileName,
                runID: runID.rawValue,
                reason: "read: \(String(describing: error))"
            )
        }
        do {
            return try TrainingRunContractCodec.makeDecoder()
                .decode(TrainingRunControlCommand.self, from: data)
        } catch {
            throw TrainingRunContractError.corruptedFile(
                name: TrainingRunContractSchema.controlCommandFileName,
                runID: runID.rawValue,
                reason: "decode: \(String(describing: error))"
            )
        }
    }

    /// Writes `control/ack-<sequence>.json` and removes the pending command.
    /// A rejection must carry a non-empty reason; unknown commands are
    /// rejected this way, never silently ignored.
    public func acknowledgeControlCommand(_ acknowledgment: TrainingRunControlAcknowledgment) throws {
        if acknowledgment.rejected {
            guard let reason = acknowledgment.reason, !reason.isEmpty else {
                throw TrainingRunContractError.invalidControlRecord(
                    reason: "rejected acknowledgment requires a non-empty reason"
                )
            }
        }
        guard FileManager.default.fileExists(atPath: controlCommandURL.path) else {
            throw TrainingRunContractError.missingFile(
                name: TrainingRunContractSchema.controlCommandFileName,
                runID: runID.rawValue
            )
        }
        let ackURL = controlDirectoryURL.appendingPathComponent(
            TrainingRunContractSchema.controlAckFileName(sequence: acknowledgment.sequence),
            isDirectory: false
        )
        try writeDocument(acknowledgment, to: ackURL)
        do {
            try FileManager.default.removeItem(at: controlCommandURL)
        } catch {
            throw TrainingRunContractError.writeFailed(
                path: controlCommandURL.path,
                reason: "remove: \(String(describing: error))"
            )
        }
    }

    // MARK: - Paths

    private var manifestURL: URL {
        runDirectory.appendingPathComponent(TrainingRunContractSchema.manifestFileName, isDirectory: false)
    }

    private var journalURL: URL {
        runDirectory.appendingPathComponent(TrainingRunContractSchema.journalFileName, isDirectory: false)
    }

    private var heartbeatURL: URL {
        runDirectory.appendingPathComponent(TrainingRunContractSchema.heartbeatFileName, isDirectory: false)
    }

    private var outcomeURL: URL {
        runDirectory.appendingPathComponent(TrainingRunContractSchema.outcomeFileName, isDirectory: false)
    }

    private var controlDirectoryURL: URL {
        runDirectory.appendingPathComponent(TrainingRunContractSchema.controlDirectoryName, isDirectory: true)
    }

    private var controlCommandURL: URL {
        controlDirectoryURL.appendingPathComponent(TrainingRunContractSchema.controlCommandFileName, isDirectory: false)
    }

    // MARK: - Low-level IO

    private func writeDocument<T: Encodable>(_ value: T, to url: URL) throws {
        let data: Data
        do {
            data = try TrainingRunContractCodec.makeDocumentEncoder().encode(value)
        } catch {
            throw TrainingRunContractError.writeFailed(
                path: url.path,
                reason: "encode: \(String(describing: error))"
            )
        }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw TrainingRunContractError.writeFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }
    }

    /// Appends `data` with a single `write(2)` call in `O_APPEND` mode.
    /// A short write is reported explicitly; readers will see it as a torn
    /// tail, never as silent loss.
    private func appendDatum(_ data: Data, to url: URL) throws {
        let descriptor = url.path.withCString { Darwin.open($0, O_WRONLY | O_APPEND) }
        guard descriptor >= 0 else {
            throw TrainingRunContractError.writeFailed(
                path: url.path,
                reason: "open: errno=\(errno)"
            )
        }
        let written = data.withUnsafeBytes { buffer in
            Darwin.write(descriptor, buffer.baseAddress, buffer.count)
        }
        if written != data.count {
            let code = errno
            _ = Darwin.close(descriptor)
            let reason = written < 0
                ? "write: errno=\(code)"
                : "short write: \(written)/\(data.count) bytes"
            throw TrainingRunContractError.writeFailed(path: url.path, reason: reason)
        }
        guard Darwin.close(descriptor) == 0 else {
            throw TrainingRunContractError.writeFailed(
                path: url.path,
                reason: "close: errno=\(errno)"
            )
        }
    }

    private static func trimTail(byteCount: Int, journalURL: URL) throws {
        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: journalURL)
        } catch {
            throw TrainingRunContractError.writeFailed(
                path: journalURL.path,
                reason: "open for repair: \(String(describing: error))"
            )
        }
        do {
            let end = try handle.seekToEnd()
            guard end >= UInt64(byteCount) else {
                try handle.close()
                throw TrainingRunContractError.corruptedFile(
                    name: TrainingRunContractSchema.journalFileName,
                    runID: journalURL.deletingLastPathComponent().lastPathComponent,
                    reason: "journal shrank below torn tail during repair"
                )
            }
            try handle.truncate(atOffset: end - UInt64(byteCount))
            try handle.close()
        } catch let error as TrainingRunContractError {
            throw error
        } catch {
            // The descriptor is released by FileHandle deinit on this error path.
            throw TrainingRunContractError.writeFailed(
                path: journalURL.path,
                reason: "repair: \(String(describing: error))"
            )
        }
    }
}
