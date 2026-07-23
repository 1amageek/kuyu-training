import Foundation
import Testing

@testable import KuyuTraining

@Suite("DurableSummaryTrainingRunHandle")
struct DurableSummaryTrainingRunHandleTests {
  @Test(.timeLimit(.minutes(1))) func waitWritesSummaryOutcomeBeforeReturning() async throws {
    let runID = TrainingRunID("durable-summary-complete")
    let artifactRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("durable-summary-complete-\(UUID().uuidString)", isDirectory: true)
    let expected = TrainingRunSummary(
      runID: runID,
      artifactRoot: artifactRoot,
      terminalState: .completed,
      generationCount: 1,
      candidateCount: 2
    )
    let handle = DurableSummaryTrainingRunHandle(
      wrapping: StaticTrainingRunHandle(summary: expected),
      artifactRoot: artifactRoot
    )

    let summary = try await handle.wait()
    let outcome = try TrainingRunSummaryOutcomeArtifactStore()
      .validatedArtifact(in: artifactRoot)

    #expect(summary == expected)
    #expect(outcome.summary == expected)
  }

  @Test(.timeLimit(.minutes(1))) func terminalSummaryPersistsWithoutConsumerWait() async throws {
    let runID = TrainingRunID("durable-summary-detached-consumer")
    let artifactRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "durable-summary-detached-consumer-\(UUID().uuidString)", isDirectory: true)
    let expected = TrainingRunSummary(
      runID: runID,
      artifactRoot: artifactRoot,
      terminalState: .completed,
      generationCount: 2,
      candidateCount: 4
    )
    _ = DurableSummaryTrainingRunHandle(
      wrapping: StaticTrainingRunHandle(summary: expected),
      artifactRoot: artifactRoot
    )
    let outcomeURL = artifactRoot.appendingPathComponent(
      TrainingRunSummaryOutcomeArtifact.fileName,
      isDirectory: false
    )

    for _ in 0..<100 where !FileManager.default.fileExists(atPath: outcomeURL.path) {
      try await Task.sleep(for: .milliseconds(10))
    }
    let outcome = try TrainingRunSummaryOutcomeArtifactStore()
      .validatedArtifact(in: artifactRoot)
    #expect(outcome.summary == expected)
  }

  @Test(.timeLimit(.minutes(1)))
  func workerAttemptPersistsFailedSummaryInsteadOfUnacceptedCompletion() async throws {
    let runID = TrainingRunID("durable-summary-worker-unaccepted")
    let artifactRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "durable-summary-worker-unaccepted-\(UUID().uuidString)",
      isDirectory: true
    )
    let identity = TrainingRunWorkerAttemptIdentity(
      launchID: UUID(),
      attemptID: UUID(),
      launchSHA256Digest: String(repeating: "a", count: 64)
    )
    let handle = DurableSummaryTrainingRunHandle(
      wrapping: StaticTrainingRunHandle(
        summary: TrainingRunSummary(
          runID: runID,
          artifactRoot: artifactRoot,
          terminalState: .completed,
          generationCount: 2,
          candidateCount: 8
        )
      ),
      artifactRoot: artifactRoot,
      workerAttemptIdentity: identity
    )

    let summary = try await handle.wait()
    let outcome = try TrainingRunSummaryOutcomeArtifactStore().validatedArtifact(
      in: artifactRoot,
      expectedRunID: runID,
      expectedWorkerAttemptIdentity: identity
    )

    #expect(summary.terminalState == .failed)
    #expect(summary.generationCount == 2)
    #expect(summary.candidateCount == 8)
    #expect(summary.failureReasons == [
      "training worker completed without an accepted checkpoint"
    ])
    #expect(outcome.summary == summary)
  }

  @Test(.timeLimit(.minutes(1))) func waitRejectsNonTerminalSummaryBeforeReturning() async throws {
    let runID = TrainingRunID("durable-summary-running")
    let artifactRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("durable-summary-running-\(UUID().uuidString)", isDirectory: true)
    let handle = DurableSummaryTrainingRunHandle(
      wrapping: StaticTrainingRunHandle(
        summary: TrainingRunSummary(
          runID: runID,
          artifactRoot: artifactRoot,
          terminalState: .running
        )),
      artifactRoot: artifactRoot
    )

    await #expect(
      throws: TrainingRunSummaryOutcomeArtifactStore.StoreError
        .invalidArtifact(.nonTerminalState(.running))
    ) {
      _ = try await handle.wait()
    }
    let outcomeURL = artifactRoot.appendingPathComponent(
      TrainingRunSummaryOutcomeArtifact.fileName,
      isDirectory: false
    )
    #expect(!FileManager.default.fileExists(atPath: outcomeURL.path))
  }

  @Test(.timeLimit(.minutes(1))) func waitRejectsSummaryOutsideBoundArtifactRoot() async throws {
    let runID = TrainingRunID("durable-summary-root-mismatch")
    let artifactRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("durable-summary-bound-\(UUID().uuidString)", isDirectory: true)
    let redirectedRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("durable-summary-redirected-\(UUID().uuidString)", isDirectory: true)
    let handle = DurableSummaryTrainingRunHandle(
      wrapping: StaticTrainingRunHandle(
        summary: TrainingRunSummary(
          runID: runID,
          artifactRoot: redirectedRoot,
          terminalState: .completed
        )),
      artifactRoot: artifactRoot
    )

    await #expect(
      throws: TrainingRunSummaryOutcomeArtifactStore.StoreError
        .invalidArtifact(
          .artifactRootMismatch(
            expected: artifactRoot.standardizedFileURL.resolvingSymlinksInPath().path,
            actual: redirectedRoot.standardizedFileURL.resolvingSymlinksInPath().path
          ))
    ) {
      _ = try await handle.wait()
    }
    for root in [artifactRoot, redirectedRoot] {
      let outcomeURL = root.appendingPathComponent(
        TrainingRunSummaryOutcomeArtifact.fileName,
        isDirectory: false
      )
      #expect(!FileManager.default.fileExists(atPath: outcomeURL.path))
    }
  }

  @Test(.timeLimit(.minutes(1))) func waitRejectsSummaryForDifferentRun() async throws {
    let runID = TrainingRunID("durable-summary-run-id")
    let artifactRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("durable-summary-run-id-\(UUID().uuidString)", isDirectory: true)
    let handle = DurableSummaryTrainingRunHandle(
      wrapping: MismatchedSummaryTrainingRunHandle(
        runID: runID,
        summary: TrainingRunSummary(
          runID: TrainingRunID("different-run"),
          artifactRoot: artifactRoot,
          terminalState: .completed
        )
      ),
      artifactRoot: artifactRoot
    )

    await #expect(
      throws: TrainingRunSummaryOutcomeArtifactStore.StoreError
        .invalidArtifact(
          .runIDMismatch(
            expected: runID.rawValue,
            actual: "different-run"
          ))
    ) {
      _ = try await handle.wait()
    }
  }

  @Test(.timeLimit(.minutes(1))) func waitWritesCancelledSummaryOutcome() async throws {
    let runID = TrainingRunID("durable-summary-cancelled")
    let artifactRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("durable-summary-cancelled-\(UUID().uuidString)", isDirectory: true)
    let expected = TrainingRunSummary(
      runID: runID,
      artifactRoot: artifactRoot,
      terminalState: .cancelled,
      failureReasons: ["cancelled"]
    )
    let handle = DurableSummaryTrainingRunHandle(
      wrapping: StaticTrainingRunHandle(summary: expected),
      artifactRoot: artifactRoot
    )

    let summary = try await handle.wait()
    let outcome = try TrainingRunSummaryOutcomeArtifactStore()
      .validatedArtifact(in: artifactRoot)

    #expect(summary == expected)
    #expect(outcome.summary == expected)
  }

  @Test(.timeLimit(.minutes(1))) func thrownFailureWritesTerminalSummaryBeforeRethrowing()
    async throws
  {
    let runID = TrainingRunID("durable-summary-failed")
    let artifactRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("durable-summary-failed-\(UUID().uuidString)", isDirectory: true)
    let handle = DurableSummaryTrainingRunHandle(
      wrapping: ThrowingTrainingRunHandle(runID: runID),
      artifactRoot: artifactRoot
    )

    await #expect(throws: DurableSummaryTestError.failed) {
      _ = try await handle.wait()
    }
    let outcome = try TrainingRunSummaryOutcomeArtifactStore()
      .validatedArtifact(in: artifactRoot)
    #expect(outcome.summary.runID == runID)
    #expect(outcome.summary.terminalState == .failed)
    #expect(outcome.summary.failureReasons == [String(describing: DurableSummaryTestError.failed)])
  }
}

private enum DurableSummaryTestError: Error {
  case failed
}

private final class ThrowingTrainingRunHandle: TrainingRunHandle, Sendable {
  let runID: TrainingRunID
  let progress = Progress(totalUnitCount: 1)
  let events: AsyncStream<TrainingRunEvent>

  init(runID: TrainingRunID) {
    self.runID = runID
    self.events = AsyncStream { continuation in
      continuation.finish()
    }
  }

  func cancel() {}

  func wait() async throws -> TrainingRunSummary {
    throw DurableSummaryTestError.failed
  }

  func shutdown() async {}
}

private final class StaticTrainingRunHandle: TrainingRunHandle, Sendable {
  let runID: TrainingRunID
  let progress: Progress
  let events: AsyncStream<TrainingRunEvent>

  private let summary: TrainingRunSummary

  init(summary: TrainingRunSummary) {
    self.runID = summary.runID
    self.progress = Progress(totalUnitCount: 1)
    self.events = AsyncStream { continuation in
      continuation.finish()
    }
    self.summary = summary
  }

  func cancel() {}

  func wait() async throws -> TrainingRunSummary {
    summary
  }

  func shutdown() async {}
}

private final class MismatchedSummaryTrainingRunHandle: TrainingRunHandle, Sendable {
  let runID: TrainingRunID
  let progress = Progress(totalUnitCount: 1)
  let events: AsyncStream<TrainingRunEvent>

  private let summary: TrainingRunSummary

  init(runID: TrainingRunID, summary: TrainingRunSummary) {
    self.runID = runID
    self.summary = summary
    self.events = AsyncStream { continuation in
      continuation.finish()
    }
  }

  func cancel() {}

  func wait() async throws -> TrainingRunSummary {
    summary
  }

  func shutdown() async {}
}
