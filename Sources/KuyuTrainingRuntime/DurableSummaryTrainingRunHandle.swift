import Foundation
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingContracts
import KuyuTrainingValidation

/// Training run handle adapter that makes terminal summaries durable before
/// exposing them to callers.
public final class DurableSummaryTrainingRunHandle: TrainingRunHandle, Sendable {
  public enum DurabilityError: Error, Sendable, Equatable {
    case terminalPersistenceFailed(primary: String, persistence: String)
  }

  public let runID: TrainingRunID
  public let progress: Progress
  public let events: AsyncStream<TrainingRunEvent>

  private let base: any TrainingRunHandle
  private let completionTask: Task<TrainingRunSummary, Error>
  private let eventForwardingTask: Task<Void, Never>

  public init(
    wrapping base: any TrainingRunHandle,
    artifactRoot: URL,
    workerAttemptIdentity: TrainingRunWorkerAttemptIdentity? = nil,
    outcomeStore: TrainingRunSummaryOutcomeArtifactStore =
      TrainingRunSummaryOutcomeArtifactStore()
  ) {
    let eventPipe = AsyncStream<TrainingRunEvent>.makeStream(
      bufferingPolicy: .bufferingNewest(1_024)
    )
    self.runID = base.runID
    self.progress = base.progress
    self.events = eventPipe.stream
    self.base = base
    self.eventForwardingTask = Task {
      for await event in base.events {
        eventPipe.continuation.yield(event)
      }
      eventPipe.continuation.finish()
    }
    self.completionTask = Task {
      let summary: TrainingRunSummary
      do {
        summary = try await base.wait()
      } catch {
        let primaryError = error
        let cancelled = primaryError is CancellationError
        let summary = TrainingRunSummary(
          runID: base.runID,
          artifactRoot: artifactRoot,
          terminalState: cancelled ? .cancelled : .failed,
          failureReasons: [cancelled ? "cancelled" : String(describing: primaryError)]
        )
        do {
          try outcomeStore.write(
            summary: summary,
            expectedRunID: base.runID,
            workerAttemptIdentity: workerAttemptIdentity,
            to: artifactRoot
          )
        } catch {
          throw DurabilityError.terminalPersistenceFailed(
            primary: String(describing: primaryError),
            persistence: String(describing: error)
          )
        }
        throw primaryError
      }
      let durableSummary = workerAttemptIdentity == nil
        ? summary
        : TrainingRunWorkerTerminalSummaryResolver().resolvedSummary(summary)
      try outcomeStore.write(
        summary: durableSummary,
        expectedRunID: base.runID,
        workerAttemptIdentity: workerAttemptIdentity,
        to: artifactRoot
      )
      return durableSummary
    }
  }

  public func cancel() {
    base.cancel()
  }

  public func wait() async throws -> TrainingRunSummary {
    try await completionTask.value
  }

  public func shutdown() async {
    await base.shutdown()
    _ = await completionTask.result
    await eventForwardingTask.value
  }
}
