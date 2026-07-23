import Foundation
import Testing

@testable import KuyuTraining

@Suite("Training run worker security boundaries")
struct TrainingRunWorkerSecurityBoundaryTests {
  @Test(.timeLimit(.minutes(1))) func pathPolicyAuthorizesDeclaredRoots() throws {
    let roots = try Self.roots("authorized")
    let artifact = Self.artifact(
      artifactRoot: roots.artifactParent.appendingPathComponent("run", isDirectory: true),
      sourceReference: try Self.pinnedSourceReference(roots: roots)
    )
    let policy = try TrainingRunWorkerPathAuthorizationPolicy(
      allowedArtifactRoots: [roots.artifactParent],
      allowedSourceRoots: [roots.sourceParent]
    )

    try policy.validate(artifact)
  }

  @Test(.timeLimit(.minutes(1))) func pathPolicyRejectsDestinationOutsideTrustedRoot() throws {
    let roots = try Self.roots("unauthorized-destination")
    let outside = FileManager.default.temporaryDirectory
      .appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
    let artifact = Self.artifact(
      artifactRoot: outside,
      sourceReference: try Self.pinnedSourceReference(roots: roots)
    )
    let policy = try TrainingRunWorkerPathAuthorizationPolicy(
      allowedArtifactRoots: [roots.artifactParent],
      allowedSourceRoots: [roots.sourceParent]
    )

    #expect(
      throws: TrainingRunWorkerPathAuthorizationPolicy.AuthorizationError
        .unauthorizedPath(category: "artifact", path: outside.path)
    ) {
      try policy.validate(artifact)
    }
  }

  @Test(.timeLimit(.minutes(1))) func sourceVerifierDetectsCheckpointMutation() throws {
    let roots = try Self.roots("source-mutation")
    let pinned = try Self.pinnedSourceReference(roots: roots)
    let artifact = Self.artifact(
      artifactRoot: roots.artifactParent.appendingPathComponent("run", isDirectory: true),
      sourceReference: pinned
    )
    try Data("changed".utf8).write(
      to: pinned.url.appendingPathComponent("model.json", isDirectory: false)
    )

    #expect(throws: TrainingRunWorkerSourceIntegrityVerifier.VerificationError.self) {
      try TrainingRunWorkerSourceIntegrityVerifier(
        allowedSourceRoots: [roots.sourceParent]
      ).verify(artifact)
    }
  }

  @Test(.timeLimit(.minutes(1))) func launchValidatorRejectsUnpinnedResumeRoot() throws {
    let roots = try Self.roots("unpinned-resume")
    let base = Self.request(
      artifactRoot: roots.artifactParent.appendingPathComponent("run", isDirectory: true),
      sourceReference: try Self.pinnedSourceReference(roots: roots)
    )
    let resume = TrainingResumeRequest(
      runID: base.runID,
      source: .artifactRoot(roots.sourceParent),
      destinationArtifactRoot: base.artifactRoot,
      taskProfileID: base.taskProfileID,
      policyContract: base.policyContract,
      actionContract: base.actionContract
    )

    #expect(
      throws: TrainingRunWorkerLaunchArtifactValidator.ValidationError
        .unpinnedResumeSource(path: roots.sourceParent.path)
    ) {
      try TrainingRunWorkerLaunchArtifactValidator().validate(
        TrainingRunWorkerLaunchArtifact(operation: .resume(resume))
      )
    }
  }

  @Test(.timeLimit(.minutes(1))) func continuationPinsHistoryAndCheckpointBytes() throws {
    let roots = try Self.roots("pinned-continuation")
    let previousArtifactRoot = roots.sourceParent.appendingPathComponent(
      "previous-run",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: previousArtifactRoot,
      withIntermediateDirectories: true
    )
    let checkpoint = previousArtifactRoot.appendingPathComponent(
      "checkpoint",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
    try Data("model".utf8).write(
      to: checkpoint.appendingPathComponent("model.json", isDirectory: false)
    )
    let verifier = TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [roots.sourceParent]
    )
    let pinned = try verifier.pinnedReference(
      ModelBundleReference(
        bundleID: "continuation-checkpoint",
        kind: .incumbent,
        url: checkpoint
      )
    )
    let base = Self.request(
      artifactRoot: roots.artifactParent.appendingPathComponent("run", isDirectory: true),
      sourceReference: pinned
    )
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .resume(
        TrainingResumeRequest(
          runID: base.runID,
          source: .continuation(
            TrainingContinuationResumeSource(
              artifactRoot: previousArtifactRoot,
              checkpoint: pinned
            )
          ),
          destinationArtifactRoot: base.artifactRoot,
          taskProfileID: base.taskProfileID,
          policyContract: base.policyContract,
          actionContract: base.actionContract
        )
      )
    )
    let policy = try TrainingRunWorkerPathAuthorizationPolicy(
      allowedArtifactRoots: [roots.artifactParent],
      allowedSourceRoots: [roots.sourceParent]
    )

    try TrainingRunWorkerLaunchArtifactValidator().validate(artifact)
    try policy.validate(artifact)
    try verifier.verify(artifact)

    try Data("mutated".utf8).write(
      to: checkpoint.appendingPathComponent("model.json", isDirectory: false)
    )
    #expect(throws: TrainingRunWorkerSourceIntegrityVerifier.VerificationError.self) {
      try verifier.verify(artifact)
    }
  }

  @Test(.timeLimit(.minutes(1))) func outcomeStoreRejectsFinalSymbolicLink() throws {
    let roots = try Self.roots("outcome-symbolic-link")
    let artifactRoot = roots.artifactParent.appendingPathComponent("run", isDirectory: true)
    let externalRoot = roots.artifactParent.appendingPathComponent("external", isDirectory: true)
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    let runID = TrainingRunID("worker-outcome-symbolic-link")
    let externalOutcome = try TrainingRunSummaryOutcomeArtifactStore().write(
      summary: TrainingRunSummary(
        runID: runID,
        artifactRoot: externalRoot,
        terminalState: .completed
      ),
      expectedRunID: runID,
      to: externalRoot
    )
    let outcomeURL = artifactRoot.appendingPathComponent(
      TrainingRunSummaryOutcomeArtifact.fileName,
      isDirectory: false
    )
    try FileManager.default.createSymbolicLink(
      at: outcomeURL,
      withDestinationURL: externalOutcome
    )

    #expect(throws: TrainingRunSummaryOutcomeArtifactStore.StoreError.self) {
      _ = try TrainingRunSummaryOutcomeArtifactStore().validatedArtifact(
        in: artifactRoot,
        expectedRunID: runID
      )
    }
  }

  @Test(.timeLimit(.minutes(1))) func outcomeStoreRejectsBroadPermissions() throws {
    let roots = try Self.roots("outcome-permissions")
    let artifactRoot = roots.artifactParent.appendingPathComponent("run", isDirectory: true)
    let runID = TrainingRunID("worker-outcome-permissions")
    let outcomeURL = try TrainingRunSummaryOutcomeArtifactStore().write(
      summary: TrainingRunSummary(
        runID: runID,
        artifactRoot: artifactRoot,
        terminalState: .completed
      ),
      expectedRunID: runID,
      to: artifactRoot
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: outcomeURL.path
    )

    #expect(
      throws: TrainingRunSummaryOutcomeArtifactStore.StoreError
        .unsafePermissions(path: outcomeURL.path, mode: 0o644)
    ) {
      _ = try TrainingRunSummaryOutcomeArtifactStore().validatedArtifact(
        in: artifactRoot,
        expectedRunID: runID
      )
    }
  }

  @Test(.timeLimit(.minutes(1))) func outcomeStoreRejectsMissingAcceptedCheckpoint() throws {
    let roots = try Self.roots("outcome-missing-accepted-checkpoint")
    let artifactRoot = roots.artifactParent.appendingPathComponent("run", isDirectory: true)
    let checkpoint = artifactRoot.appendingPathComponent("missing", isDirectory: true)
    let runID = TrainingRunID("worker-outcome-missing-accepted-checkpoint")

    do {
      _ = try TrainingRunSummaryOutcomeArtifactStore().write(
        summary: TrainingRunSummary(
          runID: runID,
          artifactRoot: artifactRoot,
          terminalState: .completed,
          acceptedCheckpoint: ModelBundleReference(
            bundleID: "missing",
            kind: .accepted,
            url: checkpoint,
            contentHash: String(repeating: "a", count: 64)
          )
        ),
        expectedRunID: runID,
        to: artifactRoot
      )
      Issue.record("Expected a missing accepted checkpoint to be rejected")
    } catch let error as TrainingRunSummaryOutcomeArtifactStore.StoreError {
      guard case .invalidArtifact(
        .acceptedCheckpointIntegrityFailure(let path, let reason)
      ) = error else {
        Issue.record("Unexpected store error: \(error)")
        return
      }
      #expect(path == checkpoint.path)
      #expect(reason.contains("checkpointMissing"))
    }
  }

  @Test(.timeLimit(.minutes(1))) func outcomeStoreRejectsAcceptedCheckpointDigestMismatch() throws {
    let roots = try Self.roots("outcome-accepted-checkpoint-digest")
    let artifactRoot = roots.artifactParent.appendingPathComponent("run", isDirectory: true)
    let checkpoint = artifactRoot.appendingPathComponent("accepted", isDirectory: true)
    try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
    try Data("model".utf8).write(
      to: checkpoint.appendingPathComponent("model.json", isDirectory: false)
    )
    let runID = TrainingRunID("worker-outcome-accepted-checkpoint-digest")
    let expectedDigest = String(repeating: "0", count: 64)
    let actualDigest = try EvolutionCheckpointIntegrity().reference(
      checkpointID: "accepted",
      checkpointURL: checkpoint,
      artifactRoot: artifactRoot
    ).sha256Digest

    #expect(
      throws: TrainingRunSummaryOutcomeArtifactStore.StoreError.invalidArtifact(
        .acceptedCheckpointDigestMismatch(
          expected: expectedDigest,
          actual: actualDigest
        )
      )
    ) {
      _ = try TrainingRunSummaryOutcomeArtifactStore().write(
        summary: TrainingRunSummary(
          runID: runID,
          artifactRoot: artifactRoot,
          terminalState: .completed,
          acceptedCheckpoint: ModelBundleReference(
            bundleID: "accepted",
            kind: .accepted,
            url: checkpoint,
            contentHash: expectedDigest
          )
        ),
        expectedRunID: runID,
        to: artifactRoot
      )
    }
  }

  private static func pinnedSourceReference(
    roots: (sourceParent: URL, artifactParent: URL)
  ) throws -> ModelBundleReference {
    let checkpoint = roots.sourceParent.appendingPathComponent("checkpoint", isDirectory: true)
    try FileManager.default.createDirectory(
      at: checkpoint,
      withIntermediateDirectories: true
    )
    try Data("model".utf8).write(
      to: checkpoint.appendingPathComponent("model.json", isDirectory: false)
    )
    return try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [roots.sourceParent]
    ).pinnedReference(
      ModelBundleReference(
        bundleID: "source-bundle",
        kind: .source,
        url: checkpoint
      ))
  }

  private static func artifact(
    artifactRoot: URL,
    sourceReference: ModelBundleReference
  ) -> TrainingRunWorkerLaunchArtifact {
    TrainingRunWorkerLaunchArtifact(
      operation: .start(
        request(
          artifactRoot: artifactRoot,
          sourceReference: sourceReference
        ))
    )
  }

  private static func request(
    artifactRoot: URL,
    sourceReference: ModelBundleReference
  ) -> TrainingRunRequest {
    TrainingRunRequest(
      runID: TrainingRunID("worker-security"),
      artifactRoot: artifactRoot,
      taskProfileID: "lift",
      policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
      actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
      sourceBundle: sourceReference
    )
  }

  private static func roots(_ suffix: String) throws -> (
    sourceParent: URL,
    artifactParent: URL
  ) {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("worker-security-\(suffix)-\(UUID().uuidString)", isDirectory: true)
    let sourceParent = root.appendingPathComponent("sources", isDirectory: true)
    let artifactParent = root.appendingPathComponent("artifacts", isDirectory: true)
    try FileManager.default.createDirectory(
      at: sourceParent,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: artifactParent,
      withIntermediateDirectories: true
    )
    return (sourceParent, artifactParent)
  }
}
