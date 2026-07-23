import Foundation
import KuyuTrainingContracts
import Synchronization

final class TrainingRunWorkerProgressObserver: Sendable {
  private struct State: Sendable {
    var cursor: TrainingRunWorkerProgressStore.JournalCursor = .zero
    var lastSequence: UInt64 = 0
    var failed = false
    var finished = false
  }

  private final class StateBox: Sendable {
    let value = Mutex(State())
  }

  let events: AsyncStream<TrainingRunEvent>
  let progress: Progress

  private let continuation: AsyncStream<TrainingRunEvent>.Continuation
  private let pollingTask: Task<Void, Never>
  private let state: StateBox
  private let progressRoot: URL
  private let workerAttemptIdentity: TrainingRunWorkerAttemptIdentity
  private let store: TrainingRunWorkerProgressStore

  init(
    progressRoot: URL,
    workerAttemptIdentity: TrainingRunWorkerAttemptIdentity,
    pollInterval: Duration = .milliseconds(250),
    store: TrainingRunWorkerProgressStore = TrainingRunWorkerProgressStore()
  ) {
    let eventPipe = AsyncStream<TrainingRunEvent>.makeStream(
      bufferingPolicy: .bufferingNewest(256)
    )
    let progress = Progress(totalUnitCount: 1_000_000)
    let state = StateBox()
    self.events = eventPipe.stream
    self.progress = progress
    self.continuation = eventPipe.continuation
    self.state = state
    self.progressRoot = progressRoot
    self.workerAttemptIdentity = workerAttemptIdentity
    self.store = store
    self.pollingTask = Task {
      while !Task.isCancelled {
        let shouldContinue = Self.publishAvailable(
          progressRoot: progressRoot,
          workerAttemptIdentity: workerAttemptIdentity,
          store: store,
          progress: progress,
          continuation: eventPipe.continuation,
          state: state
        )
        guard shouldContinue else { return }
        do {
          try await Task.sleep(for: pollInterval)
        } catch {
          return
        }
      }
    }
  }

  func finish() async {
    let shouldFinish = state.value.withLock { state in
      guard !state.finished else { return false }
      state.finished = true
      return true
    }
    guard shouldFinish else { return }
    pollingTask.cancel()
    _ = await pollingTask.result
    if !state.value.withLock({ $0.failed }) {
      _ = Self.publishAvailable(
        progressRoot: progressRoot,
        workerAttemptIdentity: workerAttemptIdentity,
        store: store,
        progress: progress,
        continuation: continuation,
        state: state
      )
    }
    continuation.finish()
  }

  func cancel() async {
    let shouldCancel = state.value.withLock { state in
      guard !state.finished else { return false }
      state.finished = true
      return true
    }
    guard shouldCancel else { return }
    pollingTask.cancel()
    _ = await pollingTask.result
    continuation.finish()
  }

  private static func publishAvailable(
    progressRoot: URL,
    workerAttemptIdentity: TrainingRunWorkerAttemptIdentity,
    store: TrainingRunWorkerProgressStore,
    progress: Progress,
    continuation: AsyncStream<TrainingRunEvent>.Continuation,
    state: StateBox
  ) -> Bool {
    do {
      var cursor = state.value.withLock { $0.cursor }
      var lastSequence = state.value.withLock { $0.lastSequence }
      while true {
        let batch = try store.journalBatch(
          in: progressRoot,
          expectedWorkerAttemptIdentity: workerAttemptIdentity,
          from: cursor
        )
        for artifact in batch.artifacts {
          let expectedSequence = lastSequence + 1
          guard artifact.sequence == expectedSequence else {
            throw ProgressObservationError.sequenceDiscontinuity(
              expected: expectedSequence,
              actual: artifact.sequence
            )
          }
          if let fraction = artifact.event.progressFraction {
            progress.completedUnitCount = Int64(
              (fraction * Double(progress.totalUnitCount)).rounded()
            )
          }
          continuation.yield(.progress(artifact.event))
          lastSequence = artifact.sequence
        }
        state.value.withLock { state in
          state.cursor = batch.nextCursor
          state.lastSequence = lastSequence
        }
        guard batch.hasMoreBytes, batch.nextCursor != cursor else {
          return true
        }
        cursor = batch.nextCursor
      }
    } catch {
      let shouldReport = state.value.withLock { state in
        guard !state.failed else { return false }
        state.failed = true
        return true
      }
      if shouldReport {
        continuation.yield(
          .progress(
            TrainingRunProgressEvent(
              event: "worker_progress_read_failed",
              status: "failed",
              failureReasons: [String(describing: error)],
              message: "Worker progress could not be read."
            )
          )
        )
      }
      return false
    }
  }

  private enum ProgressObservationError: Error, Sendable, Equatable {
    case sequenceDiscontinuity(expected: UInt64, actual: UInt64)
  }
}
