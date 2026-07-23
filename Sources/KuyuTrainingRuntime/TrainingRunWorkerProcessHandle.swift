import Darwin
import Foundation
import KuyuTrainingContracts
import KuyuTrainingValidation
import Synchronization

public final class TrainingRunWorkerProcessHandle: TrainingRunHandle, Sendable {
  public enum HandleError: Error, Sendable, Equatable {
    case processFailed(status: Int32, reason: String, errorOutput: String)
    case missingTerminalOutcome(status: Int32, errorOutput: String)
    case invalidTerminalOutcome(String)
    case cooperativeStopFailed(String)
    case administrativeTerminationFailed(String)
    case failurePersistenceFailed(primary: String, persistence: String)
  }

  public let runID: TrainingRunID
  public let progress: Progress
  public let events: AsyncStream<TrainingRunEvent>
  public let processID: Int32
  public let standardOutputURL: URL
  public let standardErrorURL: URL
  public let workerAttemptIdentity: TrainingRunWorkerAttemptIdentity

  private struct CancellationState: Sendable {
    var escalationTask: Task<Void, Never>?
    var stopRequestFailure: String?
  }

  private final class CancellationStateBox: Sendable {
    let state = Mutex(CancellationState())
  }

  private let process: TrainingRunWorkerChildProcess
  private let stopRequest: TrainingRunWorkerStopRequest?
  private let completionTask: Task<TrainingRunSummary, Error>
  private let progressObserver: TrainingRunWorkerProgressObserver
  private let cancellationState: CancellationStateBox
  private let cancellationGracePeriod: Duration
  private let terminationGracePeriod: Duration

  init(
    runID: TrainingRunID,
    artifactRoot: URL,
    progressRoot: URL,
    workerAttemptIdentity: TrainingRunWorkerAttemptIdentity,
    processID: Int32,
    standardOutputURL: URL,
    standardErrorURL: URL,
    process: TrainingRunWorkerChildProcess,
    stopRequest: TrainingRunWorkerStopRequest? = nil,
    cancellationGracePeriod: Duration = .seconds(10),
    terminationGracePeriod: Duration = .seconds(5),
    outcomeStore: TrainingRunSummaryOutcomeArtifactStore =
      TrainingRunSummaryOutcomeArtifactStore()
  ) {
    let cancellationState = CancellationStateBox()
    let progressObserver = TrainingRunWorkerProgressObserver(
      progressRoot: progressRoot,
      workerAttemptIdentity: workerAttemptIdentity
    )
    self.runID = runID
    self.progress = progressObserver.progress
    self.events = progressObserver.events
    self.processID = processID
    self.standardOutputURL = standardOutputURL
    self.standardErrorURL = standardErrorURL
    self.workerAttemptIdentity = workerAttemptIdentity
    self.process = process
    self.stopRequest = stopRequest
    self.cancellationGracePeriod = cancellationGracePeriod
    self.terminationGracePeriod = terminationGracePeriod
    self.progressObserver = progressObserver
    self.cancellationState = cancellationState
    self.completionTask = Task {
      let exit = await process.waitForExit()
      let wasAdministrativelyTerminated = await process.wasAdministrativelyTerminated()
      let administrativeTerminationError = await process.administrativeTerminationError()
      await progressObserver.finish()
      do {
        let outcome = try outcomeStore.validatedArtifact(
          in: artifactRoot,
          expectedRunID: runID,
          expectedWorkerAttemptIdentity: workerAttemptIdentity
        )
        let disposition = TrainingRunWorkerProcessDisposition(summary: outcome.summary)
        let outcomeFailure: HandleError?
        if disposition == .invalidOutcome {
          outcomeFailure = .invalidTerminalOutcome(
            "terminal state \(outcome.summary.terminalState.rawValue) does not define a valid worker process outcome"
          )
        } else if !disposition.accepts(exitStatus: exit.status)
          && !(disposition == .cancellation && wasAdministrativelyTerminated)
        {
          outcomeFailure = .invalidTerminalOutcome(
            "process exit status \(exit.status) (\(exit.reason)) contradicts \(outcome.summary.terminalState.rawValue) outcome; expected one of \(disposition.acceptedExitStatuses)"
          )
        } else {
          outcomeFailure = nil
        }
        if let administrativeTerminationError {
          let failure = HandleError.administrativeTerminationFailed(
            String(describing: administrativeTerminationError)
          )
          try Self.persistFailure(
            failure,
            errorOutput: Self.diagnosticOutput(
              standardOutputURL: standardOutputURL,
              standardErrorURL: standardErrorURL
            ),
            runID: runID,
            artifactRoot: artifactRoot,
            workerAttemptIdentity: workerAttemptIdentity,
            outcomeStore: outcomeStore
          )
          throw failure
        }
        if let stopRequestFailure = cancellationState.state.withLock({
          $0.stopRequestFailure
        }) {
          let failure = HandleError.cooperativeStopFailed(stopRequestFailure)
          try Self.persistFailure(
            failure,
            errorOutput: Self.diagnosticOutput(
              standardOutputURL: standardOutputURL,
              standardErrorURL: standardErrorURL
            ),
            runID: runID,
            artifactRoot: artifactRoot,
            workerAttemptIdentity: workerAttemptIdentity,
            outcomeStore: outcomeStore
          )
          throw failure
        }
        if let outcomeFailure {
          try Self.persistFailure(
            outcomeFailure,
            errorOutput: Self.diagnosticOutput(
              standardOutputURL: standardOutputURL,
              standardErrorURL: standardErrorURL
            ),
            runID: runID,
            artifactRoot: artifactRoot,
            workerAttemptIdentity: workerAttemptIdentity,
            outcomeStore: outcomeStore
          )
          throw outcomeFailure
        }
        progressObserver.progress.completedUnitCount =
          progressObserver.progress.totalUnitCount
        return outcome.summary
      } catch let storeError as TrainingRunSummaryOutcomeArtifactStore.StoreError {
        let errorOutput = Self.diagnosticOutput(
          standardOutputURL: standardOutputURL,
          standardErrorURL: standardErrorURL
        )
        if case .missingFile = storeError {
          if let administrativeTerminationError {
            let primary = HandleError.administrativeTerminationFailed(
              String(describing: administrativeTerminationError)
            )
            try Self.persistFailure(
              primary,
              errorOutput: errorOutput,
              runID: runID,
              artifactRoot: artifactRoot,
              workerAttemptIdentity: workerAttemptIdentity,
              outcomeStore: outcomeStore
            )
            throw primary
          }
          if let stopRequestFailure = cancellationState.state.withLock({
            $0.stopRequestFailure
          }) {
            let primary = HandleError.cooperativeStopFailed(stopRequestFailure)
            try Self.persistFailure(
              primary,
              errorOutput: errorOutput,
              runID: runID,
              artifactRoot: artifactRoot,
              workerAttemptIdentity: workerAttemptIdentity,
              outcomeStore: outcomeStore
            )
            throw primary
          }
          if wasAdministrativelyTerminated {
            let summary = TrainingRunSummary(
              runID: runID,
              artifactRoot: artifactRoot,
              terminalState: .cancelled
            )
            do {
              try outcomeStore.write(
                summary: summary,
                expectedRunID: runID,
                workerAttemptIdentity: workerAttemptIdentity,
                to: artifactRoot
              )
            } catch {
              throw HandleError.failurePersistenceFailed(
                primary: "administrative cancellation",
                persistence: String(describing: error)
              )
            }
            progressObserver.progress.completedUnitCount =
              progressObserver.progress.totalUnitCount
            return summary
          }
          let primary: HandleError
          if exit.status == 0 {
            primary = HandleError.missingTerminalOutcome(
              status: exit.status,
              errorOutput: errorOutput
            )
          } else {
            primary = HandleError.processFailed(
              status: exit.status,
              reason: exit.reason,
              errorOutput: errorOutput
            )
          }
          try Self.persistFailure(
            primary,
            errorOutput: errorOutput,
            runID: runID,
            artifactRoot: artifactRoot,
            workerAttemptIdentity: workerAttemptIdentity,
            outcomeStore: outcomeStore
          )
          throw primary
        }
        throw HandleError.invalidTerminalOutcome(String(describing: storeError))
      }
    }
  }

  public func cancel() {
    let stopRequest = self.stopRequest
    let process = self.process
    let cancellationGracePeriod = self.cancellationGracePeriod
    let terminationGracePeriod = self.terminationGracePeriod
    _ = cancellationState.state.withLock { state in
      guard state.escalationTask == nil else { return false }
      state.escalationTask = Task {
        if let stopRequest {
          do {
            try stopRequest.request()
            try await Task.sleep(for: cancellationGracePeriod)
          } catch is CancellationError {
            return
          } catch {
            cancellationState.state.withLock {
              $0.stopRequestFailure = String(describing: error)
            }
            // Fall through to process termination when the cooperative request fails.
          }
        }
        await process.terminate()
        do {
          try await Task.sleep(for: terminationGracePeriod)
        } catch {
          return
        }
        await process.hardTerminate()
      }
      return true
    }
  }

  public func wait() async throws -> TrainingRunSummary {
    try await completionTask.value
  }

  public func detach() async {
    await progressObserver.cancel()
  }

  public func shutdown() async {
    _ = await completionTask.result
    let escalationTask = cancellationState.state.withLock { $0.escalationTask }
    escalationTask?.cancel()
    _ = await escalationTask?.result
    await progressObserver.finish()
  }

  private static func tail(of url: URL, maximumByteCount: Int = 16_384) -> String {
    let descriptor = url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else {
      return "unable to open worker error log: errno=\(errno)"
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    var status = stat()
    guard fstat(descriptor, &status) == 0 else {
      return "unable to inspect worker error log: errno=\(errno)"
    }
    guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
      status.st_uid == geteuid(),
      status.st_size >= 0,
      status.st_mode & mode_t(0o077) == 0
    else {
      return "worker error log failed ownership or file-type validation"
    }

    let byteCount = min(Int64(maximumByteCount), status.st_size)
    let offset = status.st_size - byteCount
    do {
      try handle.seek(toOffset: UInt64(offset))
      let data = try handle.read(upToCount: Int(byteCount)) ?? Data()
      return String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      return "unable to read worker error log: \(error)"
    }
  }

  private static func diagnosticOutput(
    standardOutputURL: URL,
    standardErrorURL: URL,
    maximumByteCount: Int = 16_384
  ) -> String {
    let standardError = tail(of: standardErrorURL, maximumByteCount: maximumByteCount)
    let standardOutput = tail(of: standardOutputURL, maximumByteCount: maximumByteCount)
    if standardError.isEmpty {
      return standardOutput
    }
    if standardOutput.isEmpty {
      return standardError
    }
    let sectionBudget = max(0, (maximumByteCount - 32) / 2)
    return "[stderr]\n\(tail(of: standardErrorURL, maximumByteCount: sectionBudget))\n"
      + "[stdout]\n\(tail(of: standardOutputURL, maximumByteCount: sectionBudget))"
  }

  private static func persistFailure(
    _ primary: HandleError,
    errorOutput: String,
    runID: TrainingRunID,
    artifactRoot: URL,
    workerAttemptIdentity: TrainingRunWorkerAttemptIdentity,
    outcomeStore: TrainingRunSummaryOutcomeArtifactStore
  ) throws {
    let failureReason = errorOutput.isEmpty
      ? String(describing: primary)
      : "\(primary): \(errorOutput)"
    let failureSummary = TrainingRunSummary(
      runID: runID,
      artifactRoot: artifactRoot,
      terminalState: .failed,
      failureReasons: [failureReason]
    )
    do {
      try outcomeStore.write(
        summary: failureSummary,
        expectedRunID: runID,
        workerAttemptIdentity: workerAttemptIdentity,
        to: artifactRoot
      )
    } catch {
      throw HandleError.failurePersistenceFailed(
        primary: String(describing: primary),
        persistence: String(describing: error)
      )
    }
  }
}
