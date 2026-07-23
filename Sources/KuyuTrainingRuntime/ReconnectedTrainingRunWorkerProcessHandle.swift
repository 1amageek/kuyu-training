import Foundation
import KuyuTrainingContracts
import KuyuTrainingValidation
import Synchronization

public final class ReconnectedTrainingRunWorkerProcessHandle: TrainingRunHandle, Sendable {
  public enum ReconnectionError: Error, Sendable, Equatable {
    case workerExitedWithoutOutcome(runID: TrainingRunID)
    case stopRequestFailed(String)
    case stopTimedOut(runID: TrainingRunID)
    case terminalOutcomeLeaseTimedOut(runID: TrainingRunID)
  }

  private struct CancellationState: Sendable {
    var failure: String?
    var stopRequestedAt: ContinuousClock.Instant?
  }

  private final class CancellationStateBox: Sendable {
    let state = Mutex(CancellationState())
  }

  public let runID: TrainingRunID
  public let progress: Progress
  public let events: AsyncStream<TrainingRunEvent>
  public let processID: Int32
  public let workerAttemptIdentity: TrainingRunWorkerAttemptIdentity

  private let completionTask: Task<TrainingRunSummary, Error>
  private let progressObserver: TrainingRunWorkerProgressObserver
  private let stopRequest: TrainingRunWorkerStopRequest
  private let cancellationState: CancellationStateBox

  init(
    registration: TrainingRunWorkerLease.Metadata,
    progressRoot: URL,
    registrationStore: TrainingRunWorkerRegistrationStore,
    outcomeStore: TrainingRunSummaryOutcomeArtifactStore =
      TrainingRunSummaryOutcomeArtifactStore(),
    pollInterval: Duration = .milliseconds(250),
    stopGracePeriod: Duration = .seconds(10),
    terminalOutcomeLeaseGracePeriod: Duration = .seconds(30)
  ) {
    let progressObserver = TrainingRunWorkerProgressObserver(
      progressRoot: progressRoot,
      workerAttemptIdentity: registration.attemptIdentity,
      pollInterval: pollInterval
    )
    let cancellationState = CancellationStateBox()
    self.runID = registration.runID
    self.progress = progressObserver.progress
    self.events = progressObserver.events
    self.processID = registration.processID
    self.workerAttemptIdentity = registration.attemptIdentity
    self.progressObserver = progressObserver
    self.stopRequest = TrainingRunWorkerStopRequest(
      artifactRoot: registration.artifactRoot,
      launchID: registration.launchID,
      attemptID: registration.attemptID
    )
    self.cancellationState = cancellationState
    self.completionTask = Task {
      do {
        var pendingSummary: TrainingRunSummary?
        var pendingSummaryObservedAt: ContinuousClock.Instant?
        while true {
          if pendingSummary == nil {
            do {
              pendingSummary = try Self.resolvedSummary(
                registration: registration,
                outcomeStore: outcomeStore
              )
              pendingSummaryObservedAt = .now
            } catch let error as TrainingRunSummaryOutcomeArtifactStore.StoreError {
              guard case .missingFile = error else { throw error }
            }
          }

          guard try registrationStore.isActive(registration) else {
            if let pendingSummary {
              progressObserver.progress.completedUnitCount =
                progressObserver.progress.totalUnitCount
              await progressObserver.finish()
              return pendingSummary
            }
            for _ in 0..<5 {
              do {
                try await Task.sleep(for: .milliseconds(100))
              } catch {
                throw error
              }
              do {
                let summary = try Self.resolvedSummary(
                  registration: registration,
                  outcomeStore: outcomeStore
                )
                progressObserver.progress.completedUnitCount =
                  progressObserver.progress.totalUnitCount
                await progressObserver.finish()
                return summary
              } catch let error as TrainingRunSummaryOutcomeArtifactStore.StoreError {
                guard case .missingFile = error else { throw error }
              }
            }
            let summary = TrainingRunSummary(
              runID: registration.runID,
              artifactRoot: registration.artifactRoot,
              terminalState: .failed,
              failureReasons: [
                "Training worker lease became inactive without a terminal outcome."
              ]
            )
            do {
              try outcomeStore.write(
                summary: summary,
                expectedRunID: registration.runID,
                workerAttemptIdentity: registration.attemptIdentity,
                to: registration.artifactRoot
              )
            } catch {
              throw ReconnectionError.workerExitedWithoutOutcome(runID: registration.runID)
            }
            progressObserver.progress.completedUnitCount =
              progressObserver.progress.totalUnitCount
            await progressObserver.finish()
            return summary
          }
          if let pendingSummaryObservedAt,
            ContinuousClock.now - pendingSummaryObservedAt >= terminalOutcomeLeaseGracePeriod
          {
            throw ReconnectionError.terminalOutcomeLeaseTimedOut(runID: registration.runID)
          }
          if pendingSummary == nil {
            if let failure = cancellationState.state.withLock({ $0.failure }) {
              throw ReconnectionError.stopRequestFailed(failure)
            }
            if let requestedAt = cancellationState.state.withLock({ $0.stopRequestedAt }),
              ContinuousClock.now - requestedAt >= stopGracePeriod
            {
              throw ReconnectionError.stopTimedOut(runID: registration.runID)
            }
          }
          try await Task.sleep(for: pollInterval)
        }
      } catch {
        await progressObserver.finish()
        throw error
      }
    }
  }

  public func cancel() {
    do {
      try stopRequest.request()
      cancellationState.state.withLock { state in
        if state.stopRequestedAt == nil {
          state.stopRequestedAt = .now
        }
      }
    } catch {
      cancellationState.state.withLock { $0.failure = String(describing: error) }
    }
  }

  public func wait() async throws -> TrainingRunSummary {
    try await completionTask.value
  }

  public func detach() async {
    completionTask.cancel()
    await progressObserver.cancel()
  }

  public func shutdown() async {
    _ = await completionTask.result
    await progressObserver.finish()
  }

  private static func resolvedSummary(
    registration: TrainingRunWorkerLease.Metadata,
    outcomeStore: TrainingRunSummaryOutcomeArtifactStore
  ) throws -> TrainingRunSummary {
    let outcome = try outcomeStore.validatedArtifact(
      in: registration.artifactRoot,
      expectedRunID: registration.runID,
      expectedWorkerAttemptIdentity: registration.attemptIdentity
    )
    let summary = TrainingRunWorkerTerminalSummaryResolver().resolvedSummary(
      outcome.summary
    )
    if summary != outcome.summary {
      try outcomeStore.write(
        summary: summary,
        expectedRunID: registration.runID,
        workerAttemptIdentity: registration.attemptIdentity,
        to: registration.artifactRoot
      )
    }
    return summary
  }
}
