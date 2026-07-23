import Foundation
import Testing

@testable import KuyuTraining
@testable import KuyuTrainingRuntime

@Suite("Training run worker progress")
struct TrainingRunWorkerProgressTests {
  @Test(.timeLimit(.minutes(1)))
  func recorderPersistsEveryMonotonicEvent() async throws {
    let artifactRoot = try temporaryDirectory("worker-progress-recorder")
    let identity = workerAttemptIdentity()
    let recorder = try TrainingRunWorkerProgressRecorder(
      progressRoot: artifactRoot,
      workerAttemptIdentity: identity
    )

    try await recorder.record(
      TrainingRunProgressEvent(event: "generation-started", progressFraction: 0.25)
    )
    try await recorder.record(
      TrainingRunProgressEvent(event: "generation-completed", progressFraction: 0.5)
    )

    let artifact = try #require(
      try TrainingRunWorkerProgressStore().artifact(
        in: artifactRoot,
        expectedWorkerAttemptIdentity: identity
      )
    )
    #expect(artifact.sequence == 2)
    #expect(artifact.event.event == "generation-completed")
    #expect(artifact.event.progressFraction == 0.5)
    let batch = try TrainingRunWorkerProgressStore().journalBatch(
      in: artifactRoot,
      expectedWorkerAttemptIdentity: identity,
      from: .zero
    )
    #expect(batch.artifacts.map(\.sequence) == [1, 2])
    #expect(batch.artifacts.map(\.event.event) == [
      "generation-started",
      "generation-completed",
    ])
  }

  @Test(.timeLimit(.minutes(1)))
  func observerPublishesAllEventsWrittenBetweenPolls() async throws {
    let artifactRoot = try temporaryDirectory("worker-progress-burst")
    let identity = workerAttemptIdentity()
    let store = TrainingRunWorkerProgressStore()
    try await store.write(
      TrainingRunWorkerProgressArtifact(
        sequence: 1,
        workerAttemptIdentity: identity,
        event: TrainingRunProgressEvent(event: "candidate-evaluated", fitness: 1.25)
      ),
      to: artifactRoot
    )
    try await store.write(
      TrainingRunWorkerProgressArtifact(
        sequence: 2,
        workerAttemptIdentity: identity,
        event: TrainingRunProgressEvent(
          event: "candidate-rejected",
          failureReasons: ["safety regression"]
        )
      ),
      to: artifactRoot
    )
    let observer = TrainingRunWorkerProgressObserver(
      progressRoot: artifactRoot,
      workerAttemptIdentity: identity,
      pollInterval: .seconds(1)
    )
    var iterator = observer.events.makeAsyncIterator()

    let first = await iterator.next()
    let second = await iterator.next()

    guard case .progress(let firstProgress) = first,
      case .progress(let secondProgress) = second
    else {
      Issue.record("Expected both persisted progress events")
      await observer.cancel()
      return
    }
    #expect(firstProgress.event == "candidate-evaluated")
    #expect(firstProgress.fitness == 1.25)
    #expect(secondProgress.event == "candidate-rejected")
    #expect(secondProgress.failureReasons == ["safety regression"])
    await observer.cancel()
  }

  @Test(.timeLimit(.minutes(1)))
  func observerRestoresPersistedProgressIntoTheEventStream() async throws {
    let artifactRoot = try temporaryDirectory("worker-progress-observer")
    let identity = workerAttemptIdentity()
    let expected = TrainingRunProgressEvent(
      timestamp: Date(timeIntervalSince1970: 1_700_000_000),
      event: "evaluation-progress",
      phase: "evaluation",
      progressFraction: 0.42
    )
    try await TrainingRunWorkerProgressStore().write(
      TrainingRunWorkerProgressArtifact(
        sequence: 1,
        workerAttemptIdentity: identity,
        event: expected
      ),
      to: artifactRoot
    )
    let observer = TrainingRunWorkerProgressObserver(
      progressRoot: artifactRoot,
      workerAttemptIdentity: identity,
      pollInterval: .milliseconds(10)
    )
    var iterator = observer.events.makeAsyncIterator()

    let event = await iterator.next()

    guard case .progress(let actual) = event else {
      Issue.record("Expected a restored progress event")
      await observer.cancel()
      return
    }
    #expect(actual == expected)
    #expect(abs(observer.progress.fractionCompleted - 0.42) < 0.000_001)
    await observer.cancel()
  }

  @Test(.timeLimit(.minutes(1)))
  func storeRejectsAProgressFileSymbolicLink() throws {
    let artifactRoot = try temporaryDirectory("worker-progress-symbolic-link")
    let identity = workerAttemptIdentity()
    let store = TrainingRunWorkerProgressStore()
    let target = artifactRoot.appendingPathComponent("external.json", isDirectory: false)
    try Data("external".utf8).write(to: target)
    let artifactURL = store.artifactURL(
      in: artifactRoot,
      workerAttemptIdentity: identity
    )
    try FileManager.default.createDirectory(
      at: artifactURL.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.createSymbolicLink(at: artifactURL, withDestinationURL: target)

    #expect(throws: TrainingRunWorkerProgressStore.StoreError.self) {
      _ = try store.artifact(
        in: artifactRoot,
        expectedWorkerAttemptIdentity: identity
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func recorderRepairsTornTailBeforeAppending() async throws {
    let artifactRoot = try temporaryDirectory("worker-progress-torn-tail")
    let identity = workerAttemptIdentity()
    let store = TrainingRunWorkerProgressStore()
    try await store.write(
      TrainingRunWorkerProgressArtifact(
        sequence: 1,
        workerAttemptIdentity: identity,
        event: TrainingRunProgressEvent(event: "generation-started")
      ),
      to: artifactRoot
    )
    let url = store.artifactURL(
      in: artifactRoot,
      workerAttemptIdentity: identity
    )
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("{\"partial\":".utf8))
    try handle.close()

    let recorder = try TrainingRunWorkerProgressRecorder(
      progressRoot: artifactRoot,
      workerAttemptIdentity: identity
    )
    try await recorder.record(
      TrainingRunProgressEvent(event: "generation-completed")
    )

    let latest = try #require(
      try store.artifact(
        in: artifactRoot,
        expectedWorkerAttemptIdentity: identity
      )
    )
    #expect(latest.sequence == 2)
    #expect(latest.event.event == "generation-completed")
  }

  @Test(.timeLimit(.minutes(1)))
  func recorderRejectsASecondWriterForTheSameAttempt() throws {
    let artifactRoot = try temporaryDirectory("worker-progress-writer-lock")
    let identity = workerAttemptIdentity()
    let first = try TrainingRunWorkerProgressRecorder(
      progressRoot: artifactRoot,
      workerAttemptIdentity: identity
    )

    #expect(
      throws: TrainingRunWorkerProgressStore.StoreError.writerAlreadyActive(
        path: artifactRoot
          .appendingPathComponent(
            TrainingRunWorkerProgressArtifact.directoryName,
            isDirectory: true
          )
          .appendingPathComponent(
            "\(identity.launchID.uuidString).\(identity.attemptID.uuidString).writer.lock",
            isDirectory: false
          ).path
      )
    ) {
      _ = try TrainingRunWorkerProgressRecorder(
        progressRoot: artifactRoot,
        workerAttemptIdentity: identity
      )
    }
    _ = first
  }

  @Test(.timeLimit(.minutes(1)))
  func storeRotatesSegmentsWithoutLosingSequence() async throws {
    let artifactRoot = try temporaryDirectory("worker-progress-segments")
    let identity = workerAttemptIdentity()
    let store = TrainingRunWorkerProgressStore(segmentByteCount: 1)
    for sequence in UInt64(1)...2 {
      try await store.write(
        TrainingRunWorkerProgressArtifact(
          sequence: sequence,
          workerAttemptIdentity: identity,
          event: TrainingRunProgressEvent(event: "event-\(sequence)")
        ),
        to: artifactRoot
      )
    }

    #expect(FileManager.default.fileExists(
      atPath: store.artifactURL(
        in: artifactRoot,
        workerAttemptIdentity: identity,
        segmentIndex: 1
      ).path
    ))
    let latest = try #require(
      try store.artifact(
        in: artifactRoot,
        expectedWorkerAttemptIdentity: identity
      )
    )
    #expect(latest.sequence == 2)
    #expect(latest.event.event == "event-2")
  }

  private func workerAttemptIdentity() -> TrainingRunWorkerAttemptIdentity {
    TrainingRunWorkerAttemptIdentity(
      launchID: UUID(),
      attemptID: UUID(),
      launchSHA256Digest: String(repeating: "a", count: 64)
    )
  }

  private func temporaryDirectory(_ label: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "\(label)-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }
}
