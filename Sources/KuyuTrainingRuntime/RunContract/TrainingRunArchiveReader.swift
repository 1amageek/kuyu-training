import Darwin
import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

/// Read-side client of a training run directory.
///
/// CLI, UI, and tests observe runs exclusively through this type; there is no
/// client-private side channel. Readers tolerate unknown JSON fields (forward
/// compatibility) but never degrade corruption into defaults: a torn journal
/// tail is reported explicitly and every other inconsistency throws.
///
/// Clients are also controllers: `submitControlCommand(_:)` writes
/// `control/command.json`, which the single writer applies at iteration
/// boundaries.
public struct TrainingRunArchiveReader: Sendable {
    public let runDirectory: URL

    public init(runDirectory: URL) {
        self.runDirectory = runDirectory
    }

    public var runID: TrainingRunID {
        TrainingRunID(runDirectory.lastPathComponent)
    }

    // MARK: - Documents

    public func loadManifest() throws -> TrainingRunManifest {
        let manifest: TrainingRunManifest = try decodeDocument(
            relativePath: TrainingRunContractSchema.manifestFileName
        )
        guard manifest.schemaVersion == TrainingRunContractSchema.version else {
            throw TrainingRunContractError.unsupportedSchemaVersion(
                found: manifest.schemaVersion,
                supported: TrainingRunContractSchema.version
            )
        }
        guard manifest.runID.rawValue == runDirectory.lastPathComponent else {
            throw TrainingRunContractError.corruptedFile(
                name: TrainingRunContractSchema.manifestFileName,
                runID: runID.rawValue,
                reason: "manifest runID \(manifest.runID.rawValue) does not match directory name"
            )
        }
        return manifest
    }

    public func loadOutcome() throws -> TrainingRunOutcome {
        try decodeDocument(relativePath: TrainingRunContractSchema.outcomeFileName)
    }

    /// Returns nil when no heartbeat has been written yet (legal before the
    /// first iteration); throws on unreadable content.
    public func loadHeartbeat() throws -> TrainingRunHeartbeat? {
        let url = runDirectory.appendingPathComponent(
            TrainingRunContractSchema.heartbeatFileName,
            isDirectory: false
        )
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try decodeDocument(relativePath: TrainingRunContractSchema.heartbeatFileName)
    }

    // MARK: - Journal

    public func readJournal() throws -> TrainingRunJournalReadResult {
        let url = runDirectory.appendingPathComponent(
            TrainingRunContractSchema.journalFileName,
            isDirectory: false
        )
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TrainingRunContractError.missingFile(
                name: TrainingRunContractSchema.journalFileName,
                runID: runID.rawValue
            )
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TrainingRunContractError.corruptedFile(
                name: TrainingRunContractSchema.journalFileName,
                runID: runID.rawValue,
                reason: "read: \(String(describing: error))"
            )
        }
        return try Self.parseJournal(data, runID: runID.rawValue)
    }

    public func readJournalValidatingEvaluationArtifacts() throws -> TrainingRunJournalReadResult {
        let journal = try readJournal()
        try TrainingRunEvaluationArtifactReferenceValidator().validate(
            journal: journal,
            runDirectory: runDirectory
        )
        return journal
    }

    /// Parses raw journal bytes.
    ///
    /// Torn tail = bytes after the last record-terminating newline (an
    /// interrupted single-write append can only tear the unterminated tail).
    /// Invalid JSON in any newline-terminated line is genuine corruption and
    /// throws.
    static func parseJournal(_ data: Data, runID: String) throws -> TrainingRunJournalReadResult {
        guard !data.isEmpty else {
            return TrainingRunJournalReadResult(records: [], truncatedTailBytes: 0)
        }
        let newline: UInt8 = 0x0A
        guard let lastNewlineIndex = data.lastIndex(of: newline) else {
            return TrainingRunJournalReadResult(records: [], truncatedTailBytes: data.count)
        }
        let truncatedTailBytes = data.distance(from: data.index(after: lastNewlineIndex), to: data.endIndex)
        let decoder = TrainingRunContractCodec.makeDecoder()
        var records: [TrainingRunIterationRecord] = []
        var lineNumber = 0
        var lineStart = data.startIndex
        var index = data.startIndex
        while index <= lastNewlineIndex {
            if data[index] == newline {
                lineNumber += 1
                let line = data[lineStart..<index]
                guard !line.isEmpty else {
                    throw TrainingRunContractError.corruptedJournalLine(
                        lineNumber: lineNumber,
                        runID: runID,
                        reason: "empty line"
                    )
                }
                do {
                    records.append(try decoder.decode(TrainingRunIterationRecord.self, from: Data(line)))
                } catch {
                    throw TrainingRunContractError.corruptedJournalLine(
                        lineNumber: lineNumber,
                        runID: runID,
                        reason: "decode: \(String(describing: error))"
                    )
                }
                lineStart = data.index(after: index)
            }
            index = data.index(after: index)
        }
        return TrainingRunJournalReadResult(records: records, truncatedTailBytes: truncatedTailBytes)
    }

    // MARK: - Liveness

    /// Derives run liveness from `outcome.json` and the writer-process check.
    /// See `TrainingRunLiveness` for the normative derivation.
    public func liveness() throws -> TrainingRunLiveness {
        let outcome = try loadOutcome()
        if outcome.status.isTerminal {
            return .finished(outcome.status)
        }
        let heartbeat = try loadHeartbeat()
        let processIdentifier: Int32
        if let heartbeat {
            processIdentifier = heartbeat.processIdentifier
        } else {
            processIdentifier = try loadManifest().host.processIdentifier
        }
        let alive = Self.isProcessAlive(processIdentifier)
        if outcome.status == .paused {
            return .paused(processAlive: alive)
        }
        if alive {
            return .live(processIdentifier: processIdentifier)
        }
        return .interrupted(lastHeartbeat: heartbeat)
    }

    /// True when a process with `processIdentifier` exists (including
    /// processes we lack permission to signal).
    public static func isProcessAlive(_ processIdentifier: Int32) -> Bool {
        if kill(processIdentifier, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    // MARK: - Control (client side)

    /// Atomically writes `control/command.json`.
    ///
    /// Fails explicitly when another command is still pending (commands are
    /// never silently overwritten) or when `sequence` does not advance past
    /// the latest known sequence.
    public func submitControlCommand(_ command: TrainingRunControlCommand) throws {
        let controlDirectory = controlDirectoryURL
        guard FileManager.default.fileExists(atPath: controlDirectory.path) else {
            throw TrainingRunContractError.missingFile(
                name: TrainingRunContractSchema.controlDirectoryName,
                runID: runID.rawValue
            )
        }
        let outcome = try loadOutcome()
        if outcome.status.isTerminal {
            throw TrainingRunContractError.terminalRunAlreadyFinished(status: outcome.status)
        }
        let commandURL = controlCommandURL
        if FileManager.default.fileExists(atPath: commandURL.path) {
            let pending: TrainingRunControlCommand = try decodeDocument(
                relativePath: controlCommandRelativePath
            )
            throw TrainingRunContractError.pendingControlCommandExists(sequence: pending.sequence)
        }
        if let latest = try latestControlSequence(), command.sequence <= latest {
            throw TrainingRunContractError.staleControlSequence(latest: latest, found: command.sequence)
        }
        let data: Data
        do {
            data = try TrainingRunContractCodec.makeDocumentEncoder().encode(command)
        } catch {
            throw TrainingRunContractError.writeFailed(
                path: commandURL.path,
                reason: "encode: \(String(describing: error))"
            )
        }
        do {
            try data.write(to: commandURL, options: [.atomic])
        } catch {
            throw TrainingRunContractError.writeFailed(
                path: commandURL.path,
                reason: String(describing: error)
            )
        }
    }

    /// Highest control sequence visible on disk (acknowledged or pending);
    /// nil when no command was ever submitted.
    public func latestControlSequence() throws -> Int? {
        let controlDirectory = controlDirectoryURL
        guard FileManager.default.fileExists(atPath: controlDirectory.path) else {
            throw TrainingRunContractError.missingFile(
                name: TrainingRunContractSchema.controlDirectoryName,
                runID: runID.rawValue
            )
        }
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: controlDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw TrainingRunContractError.corruptedFile(
                name: TrainingRunContractSchema.controlDirectoryName,
                runID: runID.rawValue,
                reason: String(describing: error)
            )
        }
        var latest: Int?
        for entry in entries {
            guard let sequence = Self.ackSequence(fromFileName: entry.lastPathComponent) else {
                continue
            }
            latest = max(latest ?? Int.min, sequence)
        }
        if FileManager.default.fileExists(atPath: controlCommandURL.path) {
            let pending: TrainingRunControlCommand = try decodeDocument(
                relativePath: controlCommandRelativePath
            )
            latest = max(latest ?? Int.min, pending.sequence)
        }
        return latest
    }

    /// Acknowledgment for control command `sequence`; nil when not (yet)
    /// acknowledged.
    public func controlAcknowledgment(sequence: Int) throws -> TrainingRunControlAcknowledgment? {
        let relativePath = "\(TrainingRunContractSchema.controlDirectoryName)/" +
            TrainingRunContractSchema.controlAckFileName(sequence: sequence)
        let url = runDirectory.appendingPathComponent(relativePath, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try decodeDocument(relativePath: relativePath)
    }

    static func ackSequence(fromFileName name: String) -> Int? {
        guard name.hasPrefix(TrainingRunContractSchema.controlAckFilePrefix),
              name.hasSuffix(TrainingRunContractSchema.controlAckFileSuffix) else {
            return nil
        }
        let start = name.index(name.startIndex, offsetBy: TrainingRunContractSchema.controlAckFilePrefix.count)
        let end = name.index(name.endIndex, offsetBy: -TrainingRunContractSchema.controlAckFileSuffix.count)
        let digits = name[start..<end]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else {
            return nil
        }
        return Int(digits)
    }

    // MARK: - Paths and codec

    var controlDirectoryURL: URL {
        runDirectory.appendingPathComponent(TrainingRunContractSchema.controlDirectoryName, isDirectory: true)
    }

    var controlCommandURL: URL {
        controlDirectoryURL.appendingPathComponent(TrainingRunContractSchema.controlCommandFileName, isDirectory: false)
    }

    private var controlCommandRelativePath: String {
        "\(TrainingRunContractSchema.controlDirectoryName)/\(TrainingRunContractSchema.controlCommandFileName)"
    }

    private func decodeDocument<T: Decodable>(relativePath: String) throws -> T {
        let url = runDirectory.appendingPathComponent(relativePath, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TrainingRunContractError.missingFile(name: relativePath, runID: runID.rawValue)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TrainingRunContractError.corruptedFile(
                name: relativePath,
                runID: runID.rawValue,
                reason: "read: \(String(describing: error))"
            )
        }
        do {
            return try TrainingRunContractCodec.makeDecoder().decode(T.self, from: data)
        } catch {
            throw TrainingRunContractError.corruptedFile(
                name: relativePath,
                runID: runID.rawValue,
                reason: "decode: \(String(describing: error))"
            )
        }
    }
}
