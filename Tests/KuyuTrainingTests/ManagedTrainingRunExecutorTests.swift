import Foundation
import Synchronization
import Testing

@testable import KuyuTraining

@Suite("ManagedTrainingRunExecutor")
struct ManagedTrainingRunExecutorTests {
  @Test(.timeLimit(.minutes(1))) func startReturnsManagedHandleAndForwardsEvents() async throws {
    let runID = TrainingRunID("executor-start")
    let request = Self.makeRequest(runID: runID)
    let observedRunID = Mutex<TrainingRunID?>(nil)
    let expected = TrainingRunSummary(
      runID: runID,
      artifactRoot: request.artifactRoot,
      terminalState: .completed,
      generationCount: 1,
      candidateCount: 3
    )
    let executor = ManagedTrainingRunExecutor(
      start: { request, emitter in
        observedRunID.withLock { $0 = request.runID }
        emitter.emit(.iterationStarted(1))
        return expected
      },
      resume: { request, _ in
        TrainingRunSummary(
          runID: request.runID,
          artifactRoot: request.destinationArtifactRoot,
          terminalState: .failed,
          failureReasons: ["unexpected-resume"]
        )
      },
      continuationSelection: Self.makeContinuationSelection
    )

    let handle = try await executor.start(request)
    var iterator = handle.events.makeAsyncIterator()

    #expect(handle.runID == runID)
    #expect(await iterator.next() == .iterationStarted(1))
    let summary = try await handle.wait()
    let outcome = try TrainingRunSummaryOutcomeArtifactStore()
      .validatedArtifact(in: request.artifactRoot)
    #expect(summary == expected)
    #expect(outcome.summary == expected)
    #expect(await iterator.next() == nil)
    #expect(observedRunID.withLock { $0 } == runID)
  }

  @Test(.timeLimit(.minutes(1))) func startValidationFailureDoesNotLaunchOperation() async {
    let operationStarted = Mutex(false)
    let executor = ManagedTrainingRunExecutor(
      start: { request, _ in
        operationStarted.withLock { $0 = true }
        return TrainingRunSummary(
          runID: request.runID,
          artifactRoot: request.artifactRoot,
          terminalState: .completed
        )
      },
      resume: { request, _ in
        TrainingRunSummary(
          runID: request.runID,
          artifactRoot: request.destinationArtifactRoot,
          terminalState: .completed
        )
      },
      continuationSelection: Self.makeContinuationSelection,
      validate: { _ in
        throw ManagedTrainingRunExecutorTestError.rejected
      }
    )

    do {
      _ = try await executor.start(Self.makeRequest(runID: TrainingRunID("executor-rejected")))
      Issue.record("Expected validation to reject the run request.")
    } catch ManagedTrainingRunExecutorTestError.rejected {
      #expect(operationStarted.withLock { $0 } == false)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test(.timeLimit(.minutes(1))) func resumeReturnsManagedHandleAndForwardsEvents() async throws {
    let runID = TrainingRunID("executor-resume")
    let request = TrainingResumeRequest(
      runID: runID,
      source: .artifactRoot(FileManager.default.temporaryDirectory),
      destinationArtifactRoot: FileManager.default.temporaryDirectory
        .appendingPathComponent("executor-resume", isDirectory: true),
      policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
      actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract()
    )
    let expected = TrainingRunSummary(
      runID: runID,
      artifactRoot: request.destinationArtifactRoot,
      terminalState: .completed,
      generationCount: 2,
      candidateCount: 5
    )
    let executor = ManagedTrainingRunExecutor(
      start: { request, _ in
        TrainingRunSummary(
          runID: request.runID,
          artifactRoot: request.artifactRoot,
          terminalState: .failed,
          failureReasons: ["unexpected-start"]
        )
      },
      resume: { _, emitter in
        emitter.emit(.iterationStarted(2))
        return expected
      },
      continuationSelection: Self.makeContinuationSelection
    )

    let handle = try await executor.resume(request)
    var iterator = handle.events.makeAsyncIterator()

    #expect(handle.runID == runID)
    #expect(await iterator.next() == .iterationStarted(2))
    let summary = try await handle.wait()
    let outcome = try TrainingRunSummaryOutcomeArtifactStore()
      .validatedArtifact(in: request.destinationArtifactRoot)
    #expect(summary == expected)
    #expect(outcome.summary == expected)
    #expect(await iterator.next() == nil)
  }

  @Test(.timeLimit(.minutes(1))) func startRejectsNonTerminalSummaryBeforeOutcomePublication()
    async throws
  {
    let runID = TrainingRunID("executor-non-terminal-summary")
    let request = Self.makeRequest(runID: runID)
    let executor = ManagedTrainingRunExecutor(
      start: { request, _ in
        TrainingRunSummary(
          runID: request.runID,
          artifactRoot: request.artifactRoot,
          terminalState: .running
        )
      },
      resume: { request, _ in
        TrainingRunSummary(
          runID: request.runID,
          artifactRoot: request.destinationArtifactRoot,
          terminalState: .completed
        )
      },
      continuationSelection: Self.makeContinuationSelection
    )

    let handle = try await executor.start(request)

    await #expect(
      throws: TrainingRunSummaryOutcomeArtifactStore.StoreError
        .invalidArtifact(.nonTerminalState(.running))
    ) {
      _ = try await handle.wait()
    }
    let outcomeURL = request.artifactRoot.appendingPathComponent(
      TrainingRunSummaryOutcomeArtifact.fileName,
      isDirectory: false
    )
    #expect(!FileManager.default.fileExists(atPath: outcomeURL.path))
  }

  @Test(.timeLimit(.minutes(1))) func startRejectsSummaryOutsideRequestArtifactRoot() async throws {
    let runID = TrainingRunID("executor-root-mismatch")
    let request = Self.makeRequest(runID: runID)
    let redirectedRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("executor-redirected-\(UUID().uuidString)", isDirectory: true)
    let executor = ManagedTrainingRunExecutor(
      start: { request, _ in
        TrainingRunSummary(
          runID: request.runID,
          artifactRoot: redirectedRoot,
          terminalState: .completed
        )
      },
      resume: { request, _ in
        TrainingRunSummary(
          runID: request.runID,
          artifactRoot: request.destinationArtifactRoot,
          terminalState: .completed
        )
      },
      continuationSelection: Self.makeContinuationSelection
    )

    let handle = try await executor.start(request)

    await #expect(
      throws: TrainingRunSummaryOutcomeArtifactStore.StoreError
        .invalidArtifact(
          .artifactRootMismatch(
            expected: request.artifactRoot.standardizedFileURL.resolvingSymlinksInPath().path,
            actual: redirectedRoot.standardizedFileURL.resolvingSymlinksInPath().path
          ))
    ) {
      _ = try await handle.wait()
    }
  }

  @Test(.timeLimit(.minutes(1))) func resumeRejectsSummaryForDifferentRun() async throws {
    let runID = TrainingRunID("executor-resume-run-mismatch")
    let request = Self.makeResumeRequest(runID: runID)
    let executor = ManagedTrainingRunExecutor(
      start: { request, _ in
        TrainingRunSummary(
          runID: request.runID,
          artifactRoot: request.artifactRoot,
          terminalState: .completed
        )
      },
      resume: { request, _ in
        TrainingRunSummary(
          runID: TrainingRunID("different-run"),
          artifactRoot: request.destinationArtifactRoot,
          terminalState: .completed
        )
      },
      continuationSelection: Self.makeContinuationSelection
    )

    let handle = try await executor.resume(request)

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

  @Test(.timeLimit(.minutes(1))) func resumeValidationFailureDoesNotLaunchOperation() async {
    let operationStarted = Mutex(false)
    let executor = ManagedTrainingRunExecutor(
      start: { request, _ in
        TrainingRunSummary(
          runID: request.runID,
          artifactRoot: request.artifactRoot,
          terminalState: .completed
        )
      },
      resume: { request, _ in
        operationStarted.withLock { $0 = true }
        return TrainingRunSummary(
          runID: request.runID,
          artifactRoot: request.destinationArtifactRoot,
          terminalState: .completed
        )
      },
      continuationSelection: Self.makeContinuationSelection,
      validateResume: { _ in
        throw ManagedTrainingRunExecutorTestError.rejected
      }
    )

    do {
      _ = try await executor.resume(
        Self.makeResumeRequest(runID: TrainingRunID("executor-resume-rejected")))
      Issue.record("Expected validation to reject the resume request.")
    } catch ManagedTrainingRunExecutorTestError.rejected {
      #expect(operationStarted.withLock { $0 } == false)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test(.timeLimit(.minutes(1))) func continuationSelectionForwardsArtifactRoot() throws {
    let artifactRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("executor-selection", isDirectory: true)
    let expected = Self.makeContinuationSelection(artifactRoot)
    let executor = ManagedTrainingRunExecutor(
      start: { request, _ in
        TrainingRunSummary(
          runID: request.runID,
          artifactRoot: request.artifactRoot,
          terminalState: .completed
        )
      },
      resume: { request, _ in
        TrainingRunSummary(
          runID: request.runID,
          artifactRoot: request.destinationArtifactRoot,
          terminalState: .completed
        )
      },
      continuationSelection: Self.makeContinuationSelection
    )

    #expect(try executor.continuationSelection(from: artifactRoot) == expected)
  }

  private static func makeRequest(runID: TrainingRunID) -> TrainingRunRequest {
    TrainingRunRequest(
      runID: runID,
      artifactRoot: FileManager.default.temporaryDirectory
        .appendingPathComponent(runID.rawValue, isDirectory: true),
      taskProfileID: "lift",
      policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
      actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract()
    )
  }

  private static func makeResumeRequest(runID: TrainingRunID) -> TrainingResumeRequest {
    TrainingResumeRequest(
      runID: runID,
      source: .artifactRoot(FileManager.default.temporaryDirectory),
      destinationArtifactRoot: FileManager.default.temporaryDirectory
        .appendingPathComponent(runID.rawValue, isDirectory: true),
      policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
      actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract()
    )
  }

  private static func makeContinuationSelection(_ artifactRoot: URL)
    -> TrainingContinuationSelection
  {
    TrainingContinuationSelection(
      previousArtifactRoot: artifactRoot,
      checkpointURL: artifactRoot.appendingPathComponent("checkpoint", isDirectory: true),
      source: .bestCandidate,
      candidateID: "candidate",
      generationIndex: 1,
      scalarFitness: 0.75
    )
  }
}

private enum ManagedTrainingRunExecutorTestError: Error {
  case rejected
}
