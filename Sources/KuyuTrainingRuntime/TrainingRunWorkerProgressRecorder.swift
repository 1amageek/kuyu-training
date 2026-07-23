import Foundation
import KuyuTrainingContracts

public actor TrainingRunWorkerProgressRecorder {
  public enum RecorderError: Error, Equatable, Sendable {
    case persistenceFailed(String)
  }

  private let workerAttemptIdentity: TrainingRunWorkerAttemptIdentity
  private let writer: TrainingRunWorkerProgressStore.Writer
  private var sequence: UInt64

  public init(
    progressRoot: URL,
    workerAttemptIdentity: TrainingRunWorkerAttemptIdentity,
    store: TrainingRunWorkerProgressStore = TrainingRunWorkerProgressStore()
  ) throws {
    self.workerAttemptIdentity = workerAttemptIdentity
    let writer = try store.writer(
      in: progressRoot,
      workerAttemptIdentity: workerAttemptIdentity
    )
    self.writer = writer
    self.sequence = writer.initialSequence
  }

  public func record(_ event: TrainingRunProgressEvent) async throws {
    let nextSequence = sequence + 1
    do {
      try await writer.append(
        TrainingRunWorkerProgressArtifact(
          sequence: nextSequence,
          workerAttemptIdentity: workerAttemptIdentity,
          event: event
        )
      )
      sequence = nextSequence
    } catch {
      throw RecorderError.persistenceFailed(String(describing: error))
    }
  }
}
