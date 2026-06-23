import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation
/// Typed errors for every training run contract violation.
///
/// No reader or writer may degrade any of these into a default value; failures
/// surface to the caller (no silent fallback).
public enum TrainingRunContractError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidRunRoot(path: String, reason: String)
    case duplicateRunDirectory(path: String)
    case missingFile(name: String, runID: String)
    case corruptedFile(name: String, runID: String, reason: String)
    case corruptedJournalLine(lineNumber: Int, runID: String, reason: String)
    case tornJournalTail(byteCount: Int, runID: String)
    case nonMonotonicIteration(expected: Int, found: Int)
    case invalidManifest(reason: String)
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case invalidOutcome(reason: String)
    case pendingControlCommandExists(sequence: Int)
    case staleControlSequence(latest: Int, found: Int)
    case invalidControlRecord(reason: String)
    case runStillLive(processIdentifier: Int32)
    case terminalRunAlreadyFinished(status: TrainingRunLifecycleStatus)
    case writeFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case .invalidRunRoot(let path, let reason):
            return "invalid-run-root: \(path) (\(reason))"
        case .duplicateRunDirectory(let path):
            return "duplicate-run-directory: \(path)"
        case .missingFile(let name, let runID):
            return "missing-run-file: \(name) run=\(runID)"
        case .corruptedFile(let name, let runID, let reason):
            return "corrupted-run-file: \(name) run=\(runID) (\(reason))"
        case .corruptedJournalLine(let lineNumber, let runID, let reason):
            return "corrupted-journal-line: line=\(lineNumber) run=\(runID) (\(reason))"
        case .tornJournalTail(let byteCount, let runID):
            return "torn-journal-tail: \(byteCount) bytes run=\(runID)"
        case .nonMonotonicIteration(let expected, let found):
            return "non-monotonic-iteration: expected=\(expected) found=\(found)"
        case .invalidManifest(let reason):
            return "invalid-manifest: \(reason)"
        case .unsupportedSchemaVersion(let found, let supported):
            return "unsupported-schema-version: found=\(found) supported=\(supported)"
        case .invalidOutcome(let reason):
            return "invalid-outcome: \(reason)"
        case .pendingControlCommandExists(let sequence):
            return "pending-control-command-exists: sequence=\(sequence)"
        case .staleControlSequence(let latest, let found):
            return "stale-control-sequence: latest=\(latest) found=\(found)"
        case .invalidControlRecord(let reason):
            return "invalid-control-record: \(reason)"
        case .runStillLive(let processIdentifier):
            return "run-still-live: pid=\(processIdentifier)"
        case .terminalRunAlreadyFinished(let status):
            return "terminal-run-already-finished: status=\(status.rawValue)"
        case .writeFailed(let path, let reason):
            return "run-contract-write-failed: \(path) (\(reason))"
        }
    }
}
