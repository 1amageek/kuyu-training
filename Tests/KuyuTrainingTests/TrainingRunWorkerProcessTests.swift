import Foundation
import Synchronization
import Testing

@testable import KuyuTraining
@testable import KuyuTrainingRuntime

@Suite("Training run worker process")
struct TrainingRunWorkerProcessTests {
  @Test(.timeLimit(.minutes(1)))
  func cancellationDispositionAcceptsOnlySupportedStopSignals() {
    #expect(TrainingRunWorkerProcessDisposition.cancellation.accepts(exitStatus: 130))
    #expect(TrainingRunWorkerProcessDisposition.cancellation.accepts(exitStatus: 143))
    #expect(!TrainingRunWorkerProcessDisposition.cancellation.accepts(exitStatus: 137))
    #expect(!TrainingRunWorkerProcessDisposition.cancellation.accepts(exitStatus: 0))
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectionDispositionAcceptsOnlyTheContractExitStatus() {
    let summary = TrainingRunSummary(
      runID: TrainingRunID("worker-rejection-disposition"),
      artifactRoot: URL(fileURLWithPath: "/tmp/worker-rejection-disposition"),
      terminalState: .rejected,
      failureReasons: ["reinforcement-stage-unsafe"]
    )

    #expect(TrainingRunWorkerProcessDisposition(summary: summary) == .rejection)
    #expect(TrainingRunWorkerProcessDisposition.rejection.accepts(exitStatus: 64))
    #expect(!TrainingRunWorkerProcessDisposition.rejection.accepts(exitStatus: 0))
    #expect(!TrainingRunWorkerProcessDisposition.rejection.accepts(exitStatus: 1))
  }

  @Test(.timeLimit(.minutes(1)))
  func childProcessPersistsStandardOutputAndError() async throws {
    let directory = try temporaryDirectory("worker-process-output")
    let outputURL = directory.appendingPathComponent("stdout.log", isDirectory: false)
    let errorURL = directory.appendingPathComponent("stderr.log", isDirectory: false)
    let process = TrainingRunWorkerChildProcess()

    let processID = try await process.start(
      executableURL: URL(fileURLWithPath: "/bin/sh", isDirectory: false),
      arguments: ["-c", "printf 'worker-out'; printf 'worker-err' >&2"],
      standardOutputURL: outputURL,
      standardErrorURL: errorURL
    )
    let exit = await process.waitForExit()

    #expect(processID > 0)
    #expect(exit == TrainingRunWorkerProcessExit(status: 0, reason: "exit"))
    #expect(try String(contentsOf: outputURL, encoding: .utf8) == "worker-out")
    #expect(try String(contentsOf: errorURL, encoding: .utf8) == "worker-err")
  }

  @Test(.timeLimit(.minutes(1)))
  func childProcessRejectsBroadlyReadableOutputFiles() async throws {
    let directory = try temporaryDirectory("worker-process-output-permissions")
    let outputURL = directory.appendingPathComponent("stdout.log", isDirectory: false)
    let errorURL = directory.appendingPathComponent("stderr.log", isDirectory: false)
    try Data().write(to: outputURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: outputURL.path
    )
    let process = TrainingRunWorkerChildProcess()

    await #expect(
      throws: TrainingRunWorkerChildProcess.ProcessError.unsafeOutputPermissions(
        path: outputURL.path,
        mode: 0o644
      )
    ) {
      _ = try await process.start(
        executableURL: URL(fileURLWithPath: "/usr/bin/true", isDirectory: false),
        arguments: [],
        standardOutputURL: outputURL,
        standardErrorURL: errorURL
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func childProcessRejectsInPlaceExecutableMutation() async throws {
    let directory = try temporaryDirectory("worker-process-executable-mutation")
    let executableURL = directory.appendingPathComponent("worker", isDirectory: false)
    try FileManager.default.copyItem(
      at: URL(fileURLWithPath: "/usr/bin/true", isDirectory: false),
      to: executableURL
    )
    let expected = try TrainingRunWorkerExecutableIdentity.validated(executableURL).identity
    let handle = try FileHandle(forUpdating: executableURL)
    try handle.seek(toOffset: 0)
    let originalByte = try #require(try handle.read(upToCount: 1)?.first)
    try handle.seek(toOffset: 0)
    try handle.write(contentsOf: Data([originalByte ^ 0xff]))
    try handle.close()
    let process = TrainingRunWorkerChildProcess()

    await #expect(
      throws: TrainingRunWorkerChildProcess.ProcessError.executableChanged(
        path: executableURL.path
      )
    ) {
      _ = try await process.start(
        executableURL: executableURL,
        arguments: [],
        standardOutputURL: directory.appendingPathComponent("stdout.log"),
        standardErrorURL: directory.appendingPathComponent("stderr.log"),
        expectedExecutableIdentity: expected
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func postLaunchExecutableValidationFailureReapsTheChild() async throws {
    let directory = try temporaryDirectory("worker-process-post-launch-validation")
    let readyURL = directory.appendingPathComponent("ready", isDirectory: false)
    let survivedURL = directory.appendingPathComponent("survived", isDirectory: false)
    let validationCount = Mutex(0)
    let process = TrainingRunWorkerChildProcess { url in
      let invocation = validationCount.withLock { count in
        count += 1
        return count
      }
      if invocation == 2 {
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: readyURL.path) {
          usleep(10_000)
        }
        throw TrainingRunWorkerExecutableIdentity.IdentityError.readFailed(
          path: url.path,
          code: EIO
        )
      }
      return try TrainingRunWorkerExecutableIdentity.validated(url)
    }

    await #expect(
      throws: TrainingRunWorkerChildProcess.ProcessError.executableChanged(
        path: "/usr/bin/perl"
      )
    ) {
      _ = try await process.start(
        executableURL: URL(fileURLWithPath: "/usr/bin/perl", isDirectory: false),
        arguments: [
          "-e",
          "$SIG{TERM}='IGNORE'; open my $r, '>', $ARGV[0] or die $!; print $r 'ready'; close $r; sleep 1; open my $s, '>', $ARGV[1] or die $!; print $s 'survived'; close $s;",
          readyURL.path,
          survivedURL.path,
        ],
        standardOutputURL: directory.appendingPathComponent("stdout.log"),
        standardErrorURL: directory.appendingPathComponent("stderr.log")
      )
    }

    #expect(FileManager.default.fileExists(atPath: readyURL.path))
    #expect(await process.waitForExit().status == SIGKILL)
    try await Task.sleep(for: .seconds(1.1))
    #expect(!FileManager.default.fileExists(atPath: survivedURL.path))
  }

  @Test(.timeLimit(.minutes(1)))
  func stagedExecutableIsolatedFromSourcePathReplacement() async throws {
    let directory = try temporaryDirectory("worker-executable-stage")
    let sourceURL = directory.appendingPathComponent("source-worker", isDirectory: false)
    try FileManager.default.copyItem(
      at: URL(fileURLWithPath: "/usr/bin/true", isDirectory: false),
      to: sourceURL
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: sourceURL.path
    )
    let expected = try TrainingRunWorkerExecutableIdentity.validated(sourceURL).identity
    let launchDirectory = directory.appendingPathComponent("launch", isDirectory: true)
    try FileManager.default.createDirectory(
      at: launchDirectory,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    let stagedURL = try TrainingRunWorkerExecutableStager().stage(
      sourceExecutableURL: sourceURL,
      expectedIdentity: expected,
      in: launchDirectory
    )
    try FileManager.default.removeItem(at: sourceURL)
    try FileManager.default.copyItem(
      at: URL(fileURLWithPath: "/usr/bin/false", isDirectory: false),
      to: sourceURL
    )

    let process = TrainingRunWorkerChildProcess()
    _ = try await process.start(
      executableURL: stagedURL,
      arguments: [],
      standardOutputURL: directory.appendingPathComponent("stdout.log"),
      standardErrorURL: directory.appendingPathComponent("stderr.log")
    )

    #expect(await process.waitForExit().status == 0)
  }

  @Test(.timeLimit(.minutes(1)))
  func processHandleReturnsOnlyTheDurableBoundSummary() async throws {
    let directory = try temporaryDirectory("worker-process-summary")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let runID = TrainingRunID("worker-process-summary")
    let identity = workerAttemptIdentity()
    let acceptedCheckpoint = try acceptedCheckpoint(in: artifactRoot)
    let expected = TrainingRunSummary(
      runID: runID,
      artifactRoot: artifactRoot,
      terminalState: .completed,
      acceptedCheckpoint: acceptedCheckpoint,
      generationCount: 3,
      candidateCount: 12
    )
    _ = try TrainingRunSummaryOutcomeArtifactStore().write(
      summary: TrainingRunSummary(
        runID: runID,
        artifactRoot: artifactRoot,
        terminalState: .failed,
        failureReasons: ["stale generic outcome"]
      ),
      expectedRunID: runID,
      to: artifactRoot
    )
    _ = try TrainingRunSummaryOutcomeArtifactStore().write(
      summary: expected,
      expectedRunID: runID,
      workerAttemptIdentity: identity,
      to: artifactRoot
    )
    let outputURL = directory.appendingPathComponent("stdout.log", isDirectory: false)
    let errorURL = directory.appendingPathComponent("stderr.log", isDirectory: false)
    let process = TrainingRunWorkerChildProcess()
    let processID = try await process.start(
      executableURL: URL(fileURLWithPath: "/usr/bin/true", isDirectory: false),
      arguments: [],
      standardOutputURL: outputURL,
      standardErrorURL: errorURL
    )
    let handle = TrainingRunWorkerProcessHandle(
      runID: runID,
      artifactRoot: artifactRoot,
      progressRoot: directory,
      workerAttemptIdentity: identity,
      processID: processID,
      standardOutputURL: outputURL,
      standardErrorURL: errorURL,
      process: process
    )

    let summary = try await handle.wait()

    #expect(summary == expected)
    #expect(handle.progress.fractionCompleted == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func processHandleReturnsDurableRejectionForContractExitStatus() async throws {
    let directory = try temporaryDirectory("worker-process-rejection")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let runID = TrainingRunID("worker-process-rejection")
    let identity = workerAttemptIdentity()
    let expected = TrainingRunSummary(
      runID: runID,
      artifactRoot: artifactRoot,
      terminalState: .rejected,
      failureReasons: ["reinforcement-stage-unsafe"]
    )
    _ = try TrainingRunSummaryOutcomeArtifactStore().write(
      summary: expected,
      expectedRunID: runID,
      workerAttemptIdentity: identity,
      to: artifactRoot
    )
    let outputURL = directory.appendingPathComponent("stdout.log", isDirectory: false)
    let errorURL = directory.appendingPathComponent("stderr.log", isDirectory: false)
    let process = TrainingRunWorkerChildProcess()
    let processID = try await process.start(
      executableURL: URL(fileURLWithPath: "/bin/sh", isDirectory: false),
      arguments: ["-c", "exit 64"],
      standardOutputURL: outputURL,
      standardErrorURL: errorURL
    )
    let handle = TrainingRunWorkerProcessHandle(
      runID: runID,
      artifactRoot: artifactRoot,
      progressRoot: directory,
      workerAttemptIdentity: identity,
      processID: processID,
      standardOutputURL: outputURL,
      standardErrorURL: errorURL,
      process: process
    )

    let summary = try await handle.wait()

    #expect(summary == expected)
  }

  @Test(.timeLimit(.minutes(1)))
  func processHandleRejectsFailureExitForRejectedOutcome() async throws {
    let directory = try temporaryDirectory("worker-process-rejection-exit-mismatch")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let runID = TrainingRunID("worker-process-rejection-exit-mismatch")
    let identity = workerAttemptIdentity()
    _ = try TrainingRunSummaryOutcomeArtifactStore().write(
      summary: TrainingRunSummary(
        runID: runID,
        artifactRoot: artifactRoot,
        terminalState: .rejected,
        failureReasons: ["reinforcement-stage-unsafe"]
      ),
      expectedRunID: runID,
      workerAttemptIdentity: identity,
      to: artifactRoot
    )
    let outputURL = directory.appendingPathComponent("stdout.log", isDirectory: false)
    let errorURL = directory.appendingPathComponent("stderr.log", isDirectory: false)
    let process = TrainingRunWorkerChildProcess()
    let processID = try await process.start(
      executableURL: URL(fileURLWithPath: "/usr/bin/false", isDirectory: false),
      arguments: [],
      standardOutputURL: outputURL,
      standardErrorURL: errorURL
    )
    let handle = TrainingRunWorkerProcessHandle(
      runID: runID,
      artifactRoot: artifactRoot,
      progressRoot: directory,
      workerAttemptIdentity: identity,
      processID: processID,
      standardOutputURL: outputURL,
      standardErrorURL: errorURL,
      process: process
    )

    do {
      _ = try await handle.wait()
      Issue.record("Expected process/outcome contradiction to fail")
    } catch let error as TrainingRunWorkerProcessHandle.HandleError {
      guard case .invalidTerminalOutcome(let reason) = error else {
        Issue.record("Unexpected handle error: \(error)")
        return
      }
      #expect(reason.contains("expected one of [64]"))
    }
    let tombstone = try TrainingRunSummaryOutcomeArtifactStore().validatedArtifact(
      in: artifactRoot,
      expectedRunID: runID,
      expectedWorkerAttemptIdentity: identity
    )
    #expect(tombstone.summary.terminalState == .failed)
  }

  @Test(.timeLimit(.minutes(1)))
  func processHandleRejectsCompletedOutcomeWithoutAcceptedCheckpoint() async throws {
    let directory = try temporaryDirectory("worker-process-invalid-completed")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let runID = TrainingRunID("worker-process-invalid-completed")
    let identity = workerAttemptIdentity()
    _ = try TrainingRunSummaryOutcomeArtifactStore().write(
      summary: TrainingRunSummary(
        runID: runID,
        artifactRoot: artifactRoot,
        terminalState: .completed
      ),
      expectedRunID: runID,
      workerAttemptIdentity: identity,
      to: artifactRoot
    )
    let process = TrainingRunWorkerChildProcess()
    let outputURL = directory.appendingPathComponent("stdout.log", isDirectory: false)
    let errorURL = directory.appendingPathComponent("stderr.log", isDirectory: false)
    let processID = try await process.start(
      executableURL: URL(fileURLWithPath: "/usr/bin/false", isDirectory: false),
      arguments: [],
      standardOutputURL: outputURL,
      standardErrorURL: errorURL
    )
    let handle = TrainingRunWorkerProcessHandle(
      runID: runID,
      artifactRoot: artifactRoot,
      progressRoot: directory,
      workerAttemptIdentity: identity,
      processID: processID,
      standardOutputURL: outputURL,
      standardErrorURL: errorURL,
      process: process
    )

    await #expect(throws: TrainingRunWorkerProcessHandle.HandleError.self) {
      _ = try await handle.wait()
    }
    let tombstone = try TrainingRunSummaryOutcomeArtifactStore().validatedArtifact(
      in: artifactRoot,
      expectedRunID: runID,
      expectedWorkerAttemptIdentity: identity
    )
    #expect(tombstone.summary.terminalState == .failed)
  }

  @Test(.timeLimit(.minutes(1)))
  func processHandleRejectsFailureExitForSuccessfulOutcome() async throws {
    let directory = try temporaryDirectory("worker-process-exit-mismatch")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let runID = TrainingRunID("worker-process-exit-mismatch")
    let identity = workerAttemptIdentity()
    let acceptedCheckpoint = try acceptedCheckpoint(in: artifactRoot)
    _ = try TrainingRunSummaryOutcomeArtifactStore().write(
      summary: TrainingRunSummary(
        runID: runID,
        artifactRoot: artifactRoot,
        terminalState: .completed,
        acceptedCheckpoint: acceptedCheckpoint
      ),
      expectedRunID: runID,
      workerAttemptIdentity: identity,
      to: artifactRoot
    )
    let process = TrainingRunWorkerChildProcess()
    let outputURL = directory.appendingPathComponent("stdout.log", isDirectory: false)
    let errorURL = directory.appendingPathComponent("stderr.log", isDirectory: false)
    let processID = try await process.start(
      executableURL: URL(fileURLWithPath: "/bin/sh", isDirectory: false),
      arguments: ["-c", "exit 7"],
      standardOutputURL: outputURL,
      standardErrorURL: errorURL
    )
    let handle = TrainingRunWorkerProcessHandle(
      runID: runID,
      artifactRoot: artifactRoot,
      progressRoot: directory,
      workerAttemptIdentity: identity,
      processID: processID,
      standardOutputURL: outputURL,
      standardErrorURL: errorURL,
      process: process
    )

    do {
      _ = try await handle.wait()
      Issue.record("Expected process/outcome contradiction to fail")
    } catch let error as TrainingRunWorkerProcessHandle.HandleError {
      guard case .invalidTerminalOutcome(let reason) = error else {
        Issue.record("Unexpected handle error: \(error)")
        return
      }
      #expect(reason.contains("exit status 7"))
    }
    let tombstone = try TrainingRunSummaryOutcomeArtifactStore().validatedArtifact(
      in: artifactRoot,
      expectedRunID: runID,
      expectedWorkerAttemptIdentity: identity
    )
    #expect(tombstone.summary.terminalState == .failed)
  }

  @Test(.timeLimit(.minutes(1)))
  func processHandleReportsExitAndDurableErrorTailWhenOutcomeIsMissing() async throws {
    let directory = try temporaryDirectory("worker-process-failure")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let identity = workerAttemptIdentity()
    let outputURL = directory.appendingPathComponent("stdout.log", isDirectory: false)
    let errorURL = directory.appendingPathComponent("stderr.log", isDirectory: false)
    let process = TrainingRunWorkerChildProcess()
    let processID = try await process.start(
      executableURL: URL(fileURLWithPath: "/bin/sh", isDirectory: false),
      arguments: ["-c", "printf 'worker-failure-marker' >&2; exit 7"],
      standardOutputURL: outputURL,
      standardErrorURL: errorURL
    )
    let handle = TrainingRunWorkerProcessHandle(
      runID: TrainingRunID("worker-process-failure"),
      artifactRoot: artifactRoot,
      progressRoot: directory,
      workerAttemptIdentity: identity,
      processID: processID,
      standardOutputURL: outputURL,
      standardErrorURL: errorURL,
      process: process
    )

    do {
      _ = try await handle.wait()
      Issue.record("Expected the failed worker to be rejected")
    } catch let error as TrainingRunWorkerProcessHandle.HandleError {
      guard case .processFailed(let status, let reason, let errorOutput) = error else {
        Issue.record("Unexpected handle error: \(error)")
        return
      }
      #expect(status == 7)
      #expect(reason == "exit")
      #expect(errorOutput == "worker-failure-marker")
    }
    let tombstone = try TrainingRunSummaryOutcomeArtifactStore().validatedArtifact(
      in: artifactRoot,
      expectedRunID: TrainingRunID("worker-process-failure"),
      expectedWorkerAttemptIdentity: identity
    )
    #expect(tombstone.summary.terminalState == .failed)
  }

  @Test(.timeLimit(.minutes(1)))
  func processHandleReportsStandardOutputWhenStandardErrorIsEmpty() async throws {
    let directory = try temporaryDirectory("worker-process-stdout-failure")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let identity = workerAttemptIdentity()
    let outputURL = directory.appendingPathComponent("stdout.log", isDirectory: false)
    let errorURL = directory.appendingPathComponent("stderr.log", isDirectory: false)
    let process = TrainingRunWorkerChildProcess()
    let processID = try await process.start(
      executableURL: URL(fileURLWithPath: "/bin/sh", isDirectory: false),
      arguments: ["-c", "printf 'stdout-failure-marker'; exit 7"],
      standardOutputURL: outputURL,
      standardErrorURL: errorURL
    )
    let handle = TrainingRunWorkerProcessHandle(
      runID: TrainingRunID("worker-process-stdout-failure"),
      artifactRoot: artifactRoot,
      progressRoot: directory,
      workerAttemptIdentity: identity,
      processID: processID,
      standardOutputURL: outputURL,
      standardErrorURL: errorURL,
      process: process
    )

    do {
      _ = try await handle.wait()
      Issue.record("Expected the failed worker to be rejected")
    } catch let error as TrainingRunWorkerProcessHandle.HandleError {
      guard case .processFailed(_, _, let errorOutput) = error else {
        Issue.record("Unexpected handle error: \(error)")
        return
      }
      #expect(errorOutput == "stdout-failure-marker")
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func processFailureReadsOnlyTheBoundedErrorTail() async throws {
    let directory = try temporaryDirectory("worker-process-bounded-tail")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let identity = workerAttemptIdentity()
    let outputURL = directory.appendingPathComponent("stdout.log", isDirectory: false)
    let errorURL = directory.appendingPathComponent("stderr.log", isDirectory: false)
    let process = TrainingRunWorkerChildProcess()
    let processID = try await process.start(
      executableURL: URL(fileURLWithPath: "/bin/sh", isDirectory: false),
      arguments: [
        "-c",
        "dd if=/dev/zero bs=1024 count=128 2>/dev/null | tr '\\000' x >&2; printf 'TAIL-MARKER' >&2; exit 9",
      ],
      standardOutputURL: outputURL,
      standardErrorURL: errorURL
    )
    let handle = TrainingRunWorkerProcessHandle(
      runID: TrainingRunID("worker-process-bounded-tail"),
      artifactRoot: artifactRoot,
      progressRoot: directory,
      workerAttemptIdentity: identity,
      processID: processID,
      standardOutputURL: outputURL,
      standardErrorURL: errorURL,
      process: process
    )

    do {
      _ = try await handle.wait()
      Issue.record("Expected the failed worker to be rejected")
    } catch let error as TrainingRunWorkerProcessHandle.HandleError {
      guard case .processFailed(_, _, let errorOutput) = error else {
        Issue.record("Unexpected handle error: \(error)")
        return
      }
      #expect(errorOutput.utf8.count <= 16_384)
      #expect(errorOutput.hasSuffix("TAIL-MARKER"))
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func terminateStopsARunningChildProcess() async throws {
    let directory = try temporaryDirectory("worker-process-terminate")
    let process = TrainingRunWorkerChildProcess()
    _ = try await process.start(
      executableURL: URL(fileURLWithPath: "/bin/sleep", isDirectory: false),
      arguments: ["10"],
      standardOutputURL: directory.appendingPathComponent("stdout.log"),
      standardErrorURL: directory.appendingPathComponent("stderr.log")
    )

    await process.terminate()
    let exit = await process.waitForExit()

    #expect(exit.reason == "signal")
    #expect(exit.status != 0)
    #expect(await process.wasAdministrativelyTerminated())
  }

  @Test(.timeLimit(.minutes(1)))
  func escalatedCancellationPersistsCancelledOutcome() async throws {
    let directory = try temporaryDirectory("worker-process-cancellation-escalation")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    try FileManager.default.createDirectory(
      at: artifactRoot,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let runID = TrainingRunID("worker-process-cancellation-escalation")
    let identity = workerAttemptIdentity()
    let outputURL = directory.appendingPathComponent("stdout.log", isDirectory: false)
    let errorURL = directory.appendingPathComponent("stderr.log", isDirectory: false)
    let process = TrainingRunWorkerChildProcess()
    let processID = try await process.start(
      executableURL: URL(fileURLWithPath: "/bin/sleep", isDirectory: false),
      arguments: ["10"],
      standardOutputURL: outputURL,
      standardErrorURL: errorURL
    )
    let handle = TrainingRunWorkerProcessHandle(
      runID: runID,
      artifactRoot: artifactRoot,
      progressRoot: directory,
      workerAttemptIdentity: identity,
      processID: processID,
      standardOutputURL: outputURL,
      standardErrorURL: errorURL,
      process: process,
      stopRequest: TrainingRunWorkerStopRequest(
        artifactRoot: artifactRoot,
        launchID: identity.launchID,
        attemptID: identity.attemptID
      ),
      cancellationGracePeriod: .milliseconds(20)
    )

    handle.cancel()
    let summary = try await handle.wait()
    let artifact = try TrainingRunSummaryOutcomeArtifactStore().validatedArtifact(
      in: artifactRoot,
      expectedRunID: runID,
      expectedWorkerAttemptIdentity: identity
    )

    #expect(summary.terminalState == .cancelled)
    #expect(summary.failureReasons.isEmpty)
    #expect(artifact.summary == summary)
    #expect(TrainingRunWorkerProcessDisposition(summary: summary) == .cancellation)
  }

  @Test(.timeLimit(.minutes(1)))
  func stopChannelFailureIsNotReportedAsCleanCancellation() async throws {
    let directory = try temporaryDirectory("worker-process-stop-channel-failure")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let externalControl = directory.appendingPathComponent("external-control", isDirectory: true)
    try FileManager.default.createDirectory(
      at: artifactRoot,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.createDirectory(
      at: externalControl,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.createSymbolicLink(
      at: artifactRoot.appendingPathComponent(
        TrainingRunWorkerStopRequest.controlDirectoryName,
        isDirectory: true
      ),
      withDestinationURL: externalControl
    )
    let runID = TrainingRunID("worker-process-stop-channel-failure")
    let identity = workerAttemptIdentity()
    let outputURL = directory.appendingPathComponent("stdout.log", isDirectory: false)
    let errorURL = directory.appendingPathComponent("stderr.log", isDirectory: false)
    let process = TrainingRunWorkerChildProcess()
    let processID = try await process.start(
      executableURL: URL(fileURLWithPath: "/bin/sleep", isDirectory: false),
      arguments: ["10"],
      standardOutputURL: outputURL,
      standardErrorURL: errorURL
    )
    let handle = TrainingRunWorkerProcessHandle(
      runID: runID,
      artifactRoot: artifactRoot,
      progressRoot: directory,
      workerAttemptIdentity: identity,
      processID: processID,
      standardOutputURL: outputURL,
      standardErrorURL: errorURL,
      process: process,
      stopRequest: TrainingRunWorkerStopRequest(
        artifactRoot: artifactRoot,
        launchID: identity.launchID,
        attemptID: identity.attemptID
      )
    )

    handle.cancel()

    do {
      _ = try await handle.wait()
      Issue.record("Expected the unsafe stop channel to fail cancellation")
    } catch let error as TrainingRunWorkerProcessHandle.HandleError {
      guard case .cooperativeStopFailed(let reason) = error else {
        Issue.record("Unexpected handle error: \(error)")
        return
      }
      #expect(reason.contains("unsafeDirectory"))
    }
    let persisted = try TrainingRunSummaryOutcomeArtifactStore().validatedArtifact(
      in: artifactRoot,
      expectedRunID: runID,
      expectedWorkerAttemptIdentity: identity
    )
    #expect(persisted.summary.terminalState == .failed)
    #expect(persisted.summary.failureReasons.contains { $0.contains("unsafeDirectory") })
  }

  @Test(.timeLimit(.minutes(1)))
  func escalatedCancellationKillsWorkerThatIgnoresTermination() async throws {
    let directory = try temporaryDirectory("worker-process-hard-cancellation")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    try FileManager.default.createDirectory(
      at: artifactRoot,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let runID = TrainingRunID("worker-process-hard-cancellation")
    let identity = workerAttemptIdentity()
    let outputURL = directory.appendingPathComponent("stdout.log", isDirectory: false)
    let errorURL = directory.appendingPathComponent("stderr.log", isDirectory: false)
    let readyURL = directory.appendingPathComponent("ready", isDirectory: false)
    let process = TrainingRunWorkerChildProcess()
    let processID = try await process.start(
      executableURL: URL(fileURLWithPath: "/usr/bin/perl", isDirectory: false),
      arguments: [
        "-e",
        "$SIG{TERM}='IGNORE'; open my $f, '>', $ARGV[0] or die $!; print $f 'ready'; close $f; select undef,undef,undef,10",
        readyURL.path,
      ],
      standardOutputURL: outputURL,
      standardErrorURL: errorURL
    )
    let handle = TrainingRunWorkerProcessHandle(
      runID: runID,
      artifactRoot: artifactRoot,
      progressRoot: directory,
      workerAttemptIdentity: identity,
      processID: processID,
      standardOutputURL: outputURL,
      standardErrorURL: errorURL,
      process: process,
      stopRequest: TrainingRunWorkerStopRequest(
        artifactRoot: artifactRoot,
        launchID: identity.launchID,
        attemptID: identity.attemptID
      ),
      cancellationGracePeriod: .milliseconds(20),
      terminationGracePeriod: .milliseconds(20)
    )

    for _ in 0..<100 where !FileManager.default.fileExists(atPath: readyURL.path) {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(FileManager.default.fileExists(atPath: readyURL.path))
    handle.cancel()
    let summary = try await handle.wait()

    #expect(summary.terminalState == .cancelled)
    #expect(await process.waitForExit().status == SIGKILL)
  }

  @Test(.timeLimit(.minutes(1)))
  func unrequestedSignalRemainsAWorkerFailure() async throws {
    let directory = try temporaryDirectory("worker-process-unrequested-signal")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let runID = TrainingRunID("worker-process-unrequested-signal")
    let identity = workerAttemptIdentity()
    let outputURL = directory.appendingPathComponent("stdout.log", isDirectory: false)
    let errorURL = directory.appendingPathComponent("stderr.log", isDirectory: false)
    let process = TrainingRunWorkerChildProcess()
    let processID = try await process.start(
      executableURL: URL(fileURLWithPath: "/bin/sh", isDirectory: false),
      arguments: ["-c", "kill -TERM $$"],
      standardOutputURL: outputURL,
      standardErrorURL: errorURL
    )
    let handle = TrainingRunWorkerProcessHandle(
      runID: runID,
      artifactRoot: artifactRoot,
      progressRoot: directory,
      workerAttemptIdentity: identity,
      processID: processID,
      standardOutputURL: outputURL,
      standardErrorURL: errorURL,
      process: process
    )

    do {
      _ = try await handle.wait()
      Issue.record("Expected the signalled worker to fail")
    } catch let error as TrainingRunWorkerProcessHandle.HandleError {
      guard case .processFailed(let status, let reason, _) = error else {
        Issue.record("Unexpected handle error: \(error)")
        return
      }
      #expect(status == SIGTERM)
      #expect(reason == "signal")
    }
    let artifact = try TrainingRunSummaryOutcomeArtifactStore().validatedArtifact(
      in: artifactRoot,
      expectedRunID: runID,
      expectedWorkerAttemptIdentity: identity
    )
    #expect(artifact.summary.terminalState == .failed)
  }

  @Test(.timeLimit(.minutes(1)))
  func cacheConfigurationRejectsPathTraversalComponents() {
    #expect(
      throws: TrainingRunWorkerProcessConfiguration.ConfigurationError
        .invalidCachePathComponent("..")
    ) {
      _ = try TrainingRunWorkerProcessConfiguration.userCache(
        executableURL: URL(fileURLWithPath: "/usr/bin/true"),
        pathComponents: ["Kuyu", ".."]
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func launcherRejectsFinalExecutableSymbolicLink() async throws {
    let directory = try temporaryDirectory("worker-executable-link")
    let executableLink = directory.appendingPathComponent("worker", isDirectory: false)
    try FileManager.default.createSymbolicLink(
      at: executableLink,
      withDestinationURL: URL(fileURLWithPath: "/usr/bin/true", isDirectory: false)
    )
    let launcher = TrainingRunWorkerProcessLauncher(
      configuration: TrainingRunWorkerProcessConfiguration(
        executableURL: executableLink,
        launchRootDirectory: directory.appendingPathComponent("launches", isDirectory: true)
      )
    )
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        TrainingRunRequest(
          runID: TrainingRunID("executable-link"),
          artifactRoot: directory.appendingPathComponent("artifacts", isDirectory: true),
          taskProfileID: "lift",
          policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
          actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
          sourceBundle: ModelBundleReference(
            bundleID: "unused",
            kind: .source,
            url: directory,
            contentHash: String(repeating: "a", count: 64)
          )
        )
      )
    )

    await #expect(
      throws: TrainingRunWorkerProcessLauncher.LaunchError
        .symbolicLinkExecutable(path: executableLink.path)
    ) {
      _ = try await launcher.launch(artifact)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func registryReconnectsToAnActiveDigestBoundWorker() async throws {
    let fixture = try workerFixture("worker-registry-active")
    let handle = try #require(
      try fixture.registry.reconnect(artifactRoot: fixture.artifactRoot)
    )
    let acceptedCheckpoint = try acceptedCheckpoint(in: fixture.artifactRoot)
    let expected = TrainingRunSummary(
      runID: fixture.runID,
      artifactRoot: fixture.artifactRoot,
      terminalState: .completed,
      acceptedCheckpoint: acceptedCheckpoint,
      generationCount: 7,
      candidateCount: 28
    )
    _ = try TrainingRunSummaryOutcomeArtifactStore().write(
      summary: expected,
      expectedRunID: fixture.runID,
      workerAttemptIdentity: fixture.lease.metadata.attemptIdentity,
      to: fixture.artifactRoot
    )
    try await fixture.lease.release()

    let summary = try await handle.wait()

    #expect(summary == expected)
    #expect(handle.processID == fixture.lease.metadata.processID)
  }

  @Test(.timeLimit(.minutes(1)))
  func reconnectedHandleWaitsForLeaseReleaseAfterOutcomePublication() async throws {
    let fixture = try workerFixture("worker-registry-terminal-order")
    let handle = ReconnectedTrainingRunWorkerProcessHandle(
      registration: fixture.lease.metadata,
      progressRoot: TrainingRunWorkerLaunchArtifactStore(
        rootDirectory: fixture.launchRoot
      ).launchDirectory(for: fixture.lease.metadata.launchID),
      registrationStore: TrainingRunWorkerRegistrationStore(
        ownershipRootDirectory: fixture.launchRoot.appendingPathComponent(
          TrainingRunWorkerLease.ownershipDirectoryName,
          isDirectory: true
        )
      ),
      pollInterval: .milliseconds(20)
    )
    let expected = TrainingRunSummary(
      runID: fixture.runID,
      artifactRoot: fixture.artifactRoot,
      terminalState: .completed,
      acceptedCheckpoint: try acceptedCheckpoint(in: fixture.artifactRoot)
    )
    _ = try TrainingRunSummaryOutcomeArtifactStore().write(
      summary: expected,
      expectedRunID: fixture.runID,
      workerAttemptIdentity: fixture.lease.metadata.attemptIdentity,
      to: fixture.artifactRoot
    )
    let completion = CompletionProbe()
    let waiter = Task {
      let summary = try await handle.wait()
      await completion.markCompleted()
      return summary
    }

    try await Task.sleep(for: .milliseconds(100))
    #expect(await completion.isCompleted == false)

    try await fixture.lease.release()
    #expect(try await waiter.value == expected)
    #expect(await completion.isCompleted)
  }

  @Test(.timeLimit(.minutes(1)))
  func reconnectedHandleTreatsMissingMetadataUnderHeldLockAsActive() async throws {
    let fixture = try workerFixture("worker-registry-release-window")
    let registrationStore = TrainingRunWorkerRegistrationStore(
      ownershipRootDirectory: fixture.launchRoot.appendingPathComponent(
        TrainingRunWorkerLease.ownershipDirectoryName,
        isDirectory: true
      )
    )
    let handle = ReconnectedTrainingRunWorkerProcessHandle(
      registration: fixture.lease.metadata,
      progressRoot: TrainingRunWorkerLaunchArtifactStore(
        rootDirectory: fixture.launchRoot
      ).launchDirectory(for: fixture.lease.metadata.launchID),
      registrationStore: registrationStore,
      pollInterval: .milliseconds(20)
    )
    let expected = TrainingRunSummary(
      runID: fixture.runID,
      artifactRoot: fixture.artifactRoot,
      terminalState: .cancelled
    )
    _ = try TrainingRunSummaryOutcomeArtifactStore().write(
      summary: expected,
      expectedRunID: fixture.runID,
      workerAttemptIdentity: fixture.lease.metadata.attemptIdentity,
      to: fixture.artifactRoot
    )
    try FileManager.default.removeItem(at: fixture.lease.metadataFileURL)
    #expect(try registrationStore.isActive(fixture.lease.metadata))
    let completion = CompletionProbe()
    let waiter = Task {
      let summary = try await handle.wait()
      await completion.markCompleted()
      return summary
    }

    try await Task.sleep(for: .milliseconds(100))
    #expect(await completion.isCompleted == false)
    await #expect(throws: TrainingRunWorkerLease.LeaseError.self) {
      try await fixture.lease.release()
    }

    #expect(try await waiter.value == expected)
  }

  @Test(.timeLimit(.minutes(1)))
  func reconnectedHandlePersistsFailureForUnacceptedCompletion() async throws {
    let fixture = try workerFixture("worker-registry-unaccepted-completion")
    let handle = try #require(
      try fixture.registry.reconnect(artifactRoot: fixture.artifactRoot)
    )
    _ = try TrainingRunSummaryOutcomeArtifactStore().write(
      summary: TrainingRunSummary(
        runID: fixture.runID,
        artifactRoot: fixture.artifactRoot,
        terminalState: .completed,
        generationCount: 4,
        candidateCount: 16
      ),
      expectedRunID: fixture.runID,
      workerAttemptIdentity: fixture.lease.metadata.attemptIdentity,
      to: fixture.artifactRoot
    )
    try await fixture.lease.release()

    let summary = try await handle.wait()
    let persisted = try TrainingRunSummaryOutcomeArtifactStore().validatedArtifact(
      in: fixture.artifactRoot,
      expectedRunID: fixture.runID,
      expectedWorkerAttemptIdentity: fixture.lease.metadata.attemptIdentity
    )

    #expect(summary.terminalState == .failed)
    #expect(summary.failureReasons == [
      "training worker completed without an accepted checkpoint"
    ])
    #expect(persisted.summary == summary)
  }

  @Test(.timeLimit(.minutes(1)))
  func registryRejectsRegistrationForAnotherAttempt() async throws {
    let fixture = try workerFixture("worker-registry-attempt-mismatch")
    let original = fixture.lease.metadata
    let replacementAttemptID = UUID()
    let replacement = TrainingRunWorkerLease.Metadata(
      launchID: original.launchID,
      attemptID: replacementAttemptID,
      runID: original.runID,
      artifactRoot: original.artifactRoot,
      ownershipKey: original.ownershipKey,
      launchSHA256Digest: original.launchSHA256Digest,
      processID: original.processID,
      startedAt: original.startedAt
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(replacement).write(
      to: fixture.lease.metadataFileURL,
      options: [.atomic]
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fixture.lease.metadataFileURL.path
    )

    #expect(
      throws: TrainingRunWorkerProcessRegistry.RegistryError.attemptIDMismatch(
        expected: original.attemptID,
        actual: replacementAttemptID
      )
    ) {
      _ = try fixture.registry.reconnect(artifactRoot: fixture.artifactRoot)
    }

    try encoder.encode(original).write(
      to: fixture.lease.metadataFileURL,
      options: [.atomic]
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fixture.lease.metadataFileURL.path
    )
    try await fixture.lease.release()
  }

  @Test(.timeLimit(.minutes(1)))
  func reconnectedHandleRequestsCooperativeStop() async throws {
    let fixture = try workerFixture("worker-registry-stop")
    let handle = try #require(
      try fixture.registry.reconnect(artifactRoot: fixture.artifactRoot)
    )

    handle.cancel()

    let sentinel = TrainingRunWorkerStopRequest.sentinelURL(
      in: fixture.artifactRoot,
      launchID: fixture.lease.metadata.launchID,
      attemptID: fixture.lease.metadata.attemptID
    )
    var isDirectory: ObjCBool = true
    #expect(FileManager.default.fileExists(atPath: sentinel.path, isDirectory: &isDirectory))
    #expect(!isDirectory.boolValue)
    let expected = TrainingRunSummary(
      runID: fixture.runID,
      artifactRoot: fixture.artifactRoot,
      terminalState: .cancelled
    )
    _ = try TrainingRunSummaryOutcomeArtifactStore().write(
      summary: expected,
      expectedRunID: fixture.runID,
      workerAttemptIdentity: fixture.lease.metadata.attemptIdentity,
      to: fixture.artifactRoot
    )
    try await fixture.lease.release()
    #expect(try await handle.wait() == expected)
  }

  @Test(.timeLimit(.minutes(1)))
  func reconnectedHandleFailsWhenCooperativeStopDeadlineExpires() async throws {
    let fixture = try workerFixture("worker-registry-stop-timeout")
    let handle = ReconnectedTrainingRunWorkerProcessHandle(
      registration: fixture.lease.metadata,
      progressRoot: TrainingRunWorkerLaunchArtifactStore(
        rootDirectory: fixture.launchRoot
      ).launchDirectory(for: fixture.lease.metadata.launchID),
      registrationStore: TrainingRunWorkerRegistrationStore(
        ownershipRootDirectory: fixture.launchRoot.appendingPathComponent(
          TrainingRunWorkerLease.ownershipDirectoryName,
          isDirectory: true
        )
      ),
      pollInterval: .milliseconds(20),
      stopGracePeriod: .milliseconds(100)
    )
    let startedAt = ContinuousClock.now

    handle.cancel()

    await #expect(
      throws: ReconnectedTrainingRunWorkerProcessHandle.ReconnectionError
        .stopTimedOut(runID: fixture.runID)
    ) {
      _ = try await handle.wait()
    }
    #expect(ContinuousClock.now - startedAt < .seconds(2))
    try await fixture.lease.release()
  }

  @Test(.timeLimit(.minutes(1)))
  func reconnectedHandleWaitsForLeaseAfterCancelledOutcomePassesStopDeadline() async throws {
    let fixture = try workerFixture("worker-registry-cancelled-outcome-order")
    let handle = ReconnectedTrainingRunWorkerProcessHandle(
      registration: fixture.lease.metadata,
      progressRoot: TrainingRunWorkerLaunchArtifactStore(
        rootDirectory: fixture.launchRoot
      ).launchDirectory(for: fixture.lease.metadata.launchID),
      registrationStore: TrainingRunWorkerRegistrationStore(
        ownershipRootDirectory: fixture.launchRoot.appendingPathComponent(
          TrainingRunWorkerLease.ownershipDirectoryName,
          isDirectory: true
        )
      ),
      pollInterval: .milliseconds(10),
      stopGracePeriod: .milliseconds(50),
      terminalOutcomeLeaseGracePeriod: .seconds(1)
    )
    let expected = TrainingRunSummary(
      runID: fixture.runID,
      artifactRoot: fixture.artifactRoot,
      terminalState: .cancelled
    )

    handle.cancel()
    _ = try TrainingRunSummaryOutcomeArtifactStore().write(
      summary: expected,
      expectedRunID: fixture.runID,
      workerAttemptIdentity: fixture.lease.metadata.attemptIdentity,
      to: fixture.artifactRoot
    )
    let waiter = Task { try await handle.wait() }
    let completion = CompletionProbe()
    let observedWaiter = Task {
      let summary = try await waiter.value
      await completion.markCompleted()
      return summary
    }
    try await Task.sleep(for: .milliseconds(100))
    #expect(await completion.isCompleted == false)
    try await fixture.lease.release()

    #expect(try await observedWaiter.value == expected)
  }

  @Test(.timeLimit(.minutes(1)))
  func reconnectedHandleBoundsLeaseQuiescenceAfterTerminalOutcome() async throws {
    let fixture = try workerFixture("worker-registry-terminal-lease-timeout")
    let handle = ReconnectedTrainingRunWorkerProcessHandle(
      registration: fixture.lease.metadata,
      progressRoot: TrainingRunWorkerLaunchArtifactStore(
        rootDirectory: fixture.launchRoot
      ).launchDirectory(for: fixture.lease.metadata.launchID),
      registrationStore: TrainingRunWorkerRegistrationStore(
        ownershipRootDirectory: fixture.launchRoot.appendingPathComponent(
          TrainingRunWorkerLease.ownershipDirectoryName,
          isDirectory: true
        )
      ),
      pollInterval: .milliseconds(10),
      terminalOutcomeLeaseGracePeriod: .milliseconds(100)
    )
    let expected = TrainingRunSummary(
      runID: fixture.runID,
      artifactRoot: fixture.artifactRoot,
      terminalState: .cancelled
    )
    _ = try TrainingRunSummaryOutcomeArtifactStore().write(
      summary: expected,
      expectedRunID: fixture.runID,
      workerAttemptIdentity: fixture.lease.metadata.attemptIdentity,
      to: fixture.artifactRoot
    )

    await #expect(
      throws: ReconnectedTrainingRunWorkerProcessHandle.ReconnectionError
        .terminalOutcomeLeaseTimedOut(runID: fixture.runID)
    ) {
      _ = try await handle.wait()
    }
    try await fixture.lease.release()
  }

  @Test(.timeLimit(.minutes(1)))
  func staleHandleCannotStopOrMonitorReplacementAttempt() async throws {
    let fixture = try workerFixture("worker-registry-aba")
    let staleHandle = try #require(
      try fixture.registry.reconnect(artifactRoot: fixture.artifactRoot)
    )
    let staleMetadata = fixture.lease.metadata
    try await fixture.lease.release()

    let replacementArtifact = TrainingRunWorkerLaunchArtifact(
      operation: fixture.artifact.operation
    )
    let replacementReceipt = try TrainingRunWorkerLaunchArtifactStore(
      rootDirectory: fixture.launchRoot
    ).write(replacementArtifact)
    let replacementLease = try TrainingRunWorkerLease(
      ownershipRootDirectory: fixture.launchRoot.appendingPathComponent(
        TrainingRunWorkerLease.ownershipDirectoryName,
        isDirectory: true
      ),
      launchID: replacementArtifact.launchID,
      runID: fixture.runID,
      artifactRoot: fixture.artifactRoot,
      launchSHA256Digest: replacementReceipt.sha256Digest,
      attemptID: replacementArtifact.attemptID
    )

    staleHandle.cancel()

    let staleStop = TrainingRunWorkerStopRequest.sentinelURL(
      in: fixture.artifactRoot,
      launchID: staleMetadata.launchID,
      attemptID: staleMetadata.attemptID
    )
    let replacementStop = TrainingRunWorkerStopRequest.sentinelURL(
      in: fixture.artifactRoot,
      launchID: replacementLease.metadata.launchID,
      attemptID: replacementLease.metadata.attemptID
    )
    #expect(FileManager.default.fileExists(atPath: staleStop.path))
    #expect(!FileManager.default.fileExists(atPath: replacementStop.path))
    #expect(try await staleHandle.wait().terminalState == .failed)
    #expect(
      try TrainingRunWorkerRegistrationStore(
        ownershipRootDirectory: fixture.launchRoot.appendingPathComponent(
          TrainingRunWorkerLease.ownershipDirectoryName,
          isDirectory: true
        )
      ).isActive(replacementLease.metadata)
    )
    try await replacementLease.release()
  }

  @Test(.timeLimit(.minutes(1)))
  func registryConvertsUnlockedStaleRegistrationIntoFailedOutcome() async throws {
    let fixture = try workerFixture("worker-registry-stale")
    let metadata = fixture.lease.metadata
    let metadataFileURL = fixture.lease.metadataFileURL
    try await fixture.lease.release()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(metadata).write(to: metadataFileURL, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: metadataFileURL.path
    )

    let handle = try #require(
      try fixture.registry.reconnect(artifactRoot: fixture.artifactRoot)
    )
    let summary = try await handle.wait()

    #expect(summary.terminalState == .failed)
    #expect(summary.failureReasons.contains { $0.contains("lease became inactive") })
  }

  private func workerFixture(_ label: String) throws -> (
    runID: TrainingRunID,
    artifactRoot: URL,
    launchRoot: URL,
    artifact: TrainingRunWorkerLaunchArtifact,
    registry: TrainingRunWorkerProcessRegistry,
    lease: TrainingRunWorkerLease
  ) {
    let root = try temporaryDirectory(label)
    let launchRoot = root.appendingPathComponent("launches", isDirectory: true)
    let artifactRoot = root.appendingPathComponent("artifacts", isDirectory: true)
    let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
    try FileManager.default.createDirectory(
      at: artifactRoot,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: sourceRoot,
      withIntermediateDirectories: true
    )
    try Data("model".utf8).write(
      to: sourceRoot.appendingPathComponent("model.json", isDirectory: false)
    )
    let runID = TrainingRunID(label)
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        TrainingRunRequest(
          runID: runID,
          artifactRoot: artifactRoot,
          taskProfileID: "lift",
          policyContract: ReferenceQuadrotorLearningContracts
            .temporalCTBRPolicyContract(),
          actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
          sourceBundle: ModelBundleReference(
            bundleID: "source",
            kind: .source,
            url: sourceRoot,
            contentHash: String(repeating: "a", count: 64)
          )
        )
      )
    )
    let store = TrainingRunWorkerLaunchArtifactStore(rootDirectory: launchRoot)
    let receipt = try store.write(artifact)
    let lease = try TrainingRunWorkerLease(
      ownershipRootDirectory: launchRoot.appendingPathComponent(
        TrainingRunWorkerLease.ownershipDirectoryName,
        isDirectory: true
      ),
      launchID: artifact.launchID,
      runID: runID,
      artifactRoot: artifactRoot,
      launchSHA256Digest: receipt.sha256Digest,
      attemptID: artifact.attemptID
    )
    let configuration = TrainingRunWorkerProcessConfiguration(
      executableURL: URL(fileURLWithPath: "/usr/bin/true", isDirectory: false),
      launchRootDirectory: launchRoot
    )
    return (
      runID,
      artifactRoot,
      launchRoot,
      artifact,
      TrainingRunWorkerProcessRegistry(configuration: configuration),
      lease
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

  private func workerAttemptIdentity() -> TrainingRunWorkerAttemptIdentity {
    TrainingRunWorkerAttemptIdentity(
      launchID: UUID(),
      attemptID: UUID(),
      launchSHA256Digest: String(repeating: "a", count: 64)
    )
  }

  private func acceptedCheckpoint(in artifactRoot: URL) throws -> ModelBundleReference {
    let checkpointURL = artifactRoot.appendingPathComponent("accepted", isDirectory: true)
    try FileManager.default.createDirectory(
      at: checkpointURL,
      withIntermediateDirectories: true
    )
    try Data("accepted-model".utf8).write(
      to: checkpointURL.appendingPathComponent("model.json", isDirectory: false),
      options: [.atomic]
    )
    let reference = try EvolutionCheckpointIntegrity().reference(
      checkpointID: "accepted",
      checkpointURL: checkpointURL,
      artifactRoot: artifactRoot
    )
    return ModelBundleReference(
      bundleID: "accepted",
      kind: .accepted,
      url: checkpointURL,
      contentHash: reference.sha256Digest
    )
  }
}

private actor CompletionProbe {
  private(set) var isCompleted = false

  func markCompleted() {
    isCompleted = true
  }
}
