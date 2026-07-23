import Darwin
import Foundation
import Synchronization
import Testing

@testable import KuyuTraining

@Suite("Training run worker launch artifact")
struct TrainingRunWorkerLaunchArtifactTests {
  @Test(.timeLimit(.minutes(1))) func codecPreservesCandidateRefinement() throws {
    let refinement = TrainingCandidateRefinementPolicy(
      candidateFraction: 0.5,
      minimumCandidateCount: 2,
      retainsIncumbent: true
    )
    let configuration = TrainingRunConfiguration(
      searchScenarioSelection: TrainingScenarioSelection(
        evaluationFidelity: .screening(maximumControlStepsPerEpisode: 100)
      ),
      evolution: TrainingEvolutionSettings(candidateRefinement: refinement)
    )
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        Self.makeRequest(
          runID: TrainingRunID("worker-candidate-refinement"),
          artifactRoot: Self.temporaryDirectory("worker-candidate-refinement"),
          configuration: configuration
        )
      )
    )

    let codec = TrainingRunWorkerLaunchArtifactCodec()
    let decoded = try codec.decode(codec.encode(artifact))

    guard case .start(let request) = decoded.artifact.operation else {
      Issue.record("Expected a start operation.")
      return
    }
    #expect(request.configuration.evolution.candidateRefinement == refinement)
  }

  @Test(.timeLimit(.minutes(1))) func codecPreservesEvaluationFidelity() throws {
    let configuration = TrainingRunConfiguration(
      searchScenarioSelection: TrainingScenarioSelection(
        evaluationFidelity: .screening(maximumControlStepsPerEpisode: 750)
      ),
      acceptanceScenarioSelection: TrainingScenarioSelection(
        evaluationFidelity: .fullScenario
      )
    )
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        Self.makeRequest(
          runID: TrainingRunID("worker-evaluation-fidelity"),
          artifactRoot: Self.temporaryDirectory("worker-evaluation-fidelity"),
          configuration: configuration
        )
      )
    )

    let codec = TrainingRunWorkerLaunchArtifactCodec()
    let decoded = try codec.decode(codec.encode(artifact))

    guard case .start(let request) = decoded.artifact.operation else {
      Issue.record("Expected a start operation.")
      return
    }
    #expect(
      request.configuration.searchScenarioSelection.evaluationFidelity
        == .screening(maximumControlStepsPerEpisode: 750)
    )
    #expect(
      request.configuration.acceptanceScenarioSelection.evaluationFidelity
        == .fullScenario
    )
  }

  @Test(.timeLimit(.minutes(1))) func validatorRejectsScreeningAcceptance() {
    let configuration = TrainingRunConfiguration(
      acceptanceScenarioSelection: TrainingScenarioSelection(
        evaluationFidelity: .screening(maximumControlStepsPerEpisode: 100)
      )
    )
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        Self.makeRequest(
          runID: TrainingRunID("worker-screening-acceptance"),
          artifactRoot: Self.temporaryDirectory("worker-screening-acceptance"),
          configuration: configuration
        )
      )
    )

    #expect(
      throws: TrainingRunWorkerLaunchArtifactValidator.ValidationError
        .acceptanceRequiresFullScenario
    ) {
      try TrainingRunWorkerLaunchArtifactValidator().validate(artifact)
    }
  }

  @Test(.timeLimit(.minutes(1))) func validatorRejectsScreeningWithoutRefinement() {
    let configuration = TrainingRunConfiguration(
      searchScenarioSelection: TrainingScenarioSelection(
        evaluationFidelity: .screening(maximumControlStepsPerEpisode: 100)
      )
    )
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        Self.makeRequest(
          runID: TrainingRunID("worker-screening-without-refinement"),
          artifactRoot: Self.temporaryDirectory("worker-screening-without-refinement"),
          configuration: configuration
        )
      )
    )

    #expect(
      throws: TrainingRunWorkerLaunchArtifactValidator.ValidationError
        .screeningRequiresRefinement
    ) {
      try TrainingRunWorkerLaunchArtifactValidator().validate(artifact)
    }
  }

  @Test(.timeLimit(.minutes(1))) func validatorRejectsFullScenarioWithRefinement() {
    let configuration = TrainingRunConfiguration(
      evolution: TrainingEvolutionSettings(
        candidateRefinement: TrainingCandidateRefinementPolicy()
      )
    )
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        Self.makeRequest(
          runID: TrainingRunID("worker-full-with-refinement"),
          artifactRoot: Self.temporaryDirectory("worker-full-with-refinement"),
          configuration: configuration
        )
      )
    )

    #expect(
      throws: TrainingRunWorkerLaunchArtifactValidator.ValidationError
        .fullScenarioProhibitsRefinement
    ) {
      try TrainingRunWorkerLaunchArtifactValidator().validate(artifact)
    }
  }

  @Test(.timeLimit(.minutes(1))) func codecPreservesReinforcementStoppingContract() throws {
    let stopping = try TrainingReinforcementStoppingSettings(
      minimumIterationCount: 11,
      plateauWindow: 13,
      unsafeWindow: 2
    )
    let configuration = TrainingRunConfiguration(
      reinforcement: TrainingReinforcementSettings(
        iterations: 50,
        stopping: stopping
      )
    )
    let request = Self.makeRequest(
      runID: TrainingRunID("worker-reinforcement-stopping"),
      artifactRoot: Self.temporaryDirectory("worker-reinforcement-stopping"),
      configuration: configuration
    )
    let artifact = TrainingRunWorkerLaunchArtifact(operation: .start(request))

    let decoded = try TrainingRunWorkerLaunchArtifactCodec().decode(
      TrainingRunWorkerLaunchArtifactCodec().encode(artifact)
    )

    #expect(decoded.artifact == artifact)
    guard case .start(let decodedRequest) = decoded.artifact.operation else {
      Issue.record("Expected a start operation.")
      return
    }
    #expect(decodedRequest.configuration.reinforcement.stopping == stopping)
  }

  @Test(.timeLimit(.minutes(1))) func codecDefaultsLegacyStoppingWireContract() throws {
    let configuration = TrainingRunConfiguration(
      reinforcement: TrainingReinforcementSettings(
        iterations: 50,
        stopping: .extendedConvergence
      )
    )
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        Self.makeRequest(
          runID: TrainingRunID("worker-legacy-stopping"),
          artifactRoot: Self.temporaryDirectory("worker-legacy-stopping"),
          configuration: configuration
        )
      )
    )
    let codec = TrainingRunWorkerLaunchArtifactCodec()
    let encoded = try codec.encode(artifact)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    var operation = try #require(object["operation"] as? [String: Any])
    var startRequest = try #require(operation["startRequest"] as? [String: Any])
    var wireConfiguration = try #require(startRequest["configuration"] as? [String: Any])
    var reinforcement = try #require(wireConfiguration["reinforcement"] as? [String: Any])
    reinforcement.removeValue(forKey: "stopping")
    wireConfiguration["reinforcement"] = reinforcement
    startRequest["configuration"] = wireConfiguration
    operation["startRequest"] = startRequest
    object["operation"] = operation
    let legacyData = try JSONSerialization.data(withJSONObject: object)

    let decoded = try codec.decode(legacyData)

    guard case .start(let request) = decoded.artifact.operation else {
      Issue.record("Expected a start operation.")
      return
    }
    #expect(request.configuration.reinforcement.stopping == .conservative)
  }

  @Test(.timeLimit(.minutes(1))) func storeRoundTripsDigestBoundStartRequest() throws {
    let launchRoot = Self.temporaryDirectory("worker-launch-start")
    let artifactRoot = Self.temporaryDirectory("worker-artifacts-start")
    let request = Self.makeRequest(
      runID: TrainingRunID("worker-start"),
      artifactRoot: artifactRoot
    )
    let artifact = TrainingRunWorkerLaunchArtifact(
      launchID: UUID(),
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      operation: .start(request)
    )
    let store = TrainingRunWorkerLaunchArtifactStore(rootDirectory: launchRoot)

    let receipt = try store.write(artifact)
    let reloaded = try store.validatedArtifact(
      launchID: artifact.launchID,
      expectedSHA256Digest: receipt.sha256Digest
    )

    #expect(reloaded == artifact)
    #expect(receipt.fileURL == store.artifactURL(for: artifact.launchID))
    #expect(receipt.sha256Digest.count == 64)
  }

  @Test(.timeLimit(.minutes(1))) func codecDispatchesUnsupportedVersionBeforePayloadDecode() {
    let malformedFutureArtifact = Data(
      """
      {
        "schemaVersion": 999,
        "launchID": false,
        "createdAt": [],
        "operation": "not-an-operation"
      }
      """.utf8
    )

    #expect(
      throws: TrainingRunWorkerLaunchArtifactCodec.CodecError
        .unsupportedSchemaVersion(999)
    ) {
      _ = try TrainingRunWorkerLaunchArtifactCodec().decode(malformedFutureArtifact)
    }
  }

  @Test(.timeLimit(.minutes(1))) func codecRejectsMissingVersionHeader() {
    let artifactWithoutVersion = Data("{\"operation\":{}}".utf8)

    #expect(throws: TrainingRunWorkerLaunchArtifactCodec.CodecError.self) {
      _ = try TrainingRunWorkerLaunchArtifactCodec().decode(artifactWithoutVersion)
    }
  }

  @Test(.timeLimit(.minutes(1))) func codecRejectsInvalidRawConfigurationBeforeClamping() throws {
    let artifact = TrainingRunWorkerLaunchArtifact(
      launchID: UUID(uuidString: "D0832EF5-CF0E-4FA4-B2E9-3E62403E6B54")!,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      operation: .start(
        Self.makeRequest(
          runID: TrainingRunID("worker-invalid-resource-plan"),
          artifactRoot: URL(fileURLWithPath: "/tmp/worker-invalid-resource-plan", isDirectory: true)
        )
      )
    )
    let codec = TrainingRunWorkerLaunchArtifactCodec()
    let encoded = try codec.encode(artifact)
    let text = try #require(String(data: encoded, encoding: .utf8))
    #expect(text.contains("\"workerCount\" : 2"))
    let invalidText = text.replacingOccurrences(
      of: "\"workerCount\" : 2",
      with: "\"workerCount\" : 0"
    )

    #expect(throws: TrainingRunWorkerLaunchArtifactCodec.CodecError.self) {
      _ = try codec.decode(Data(invalidText.utf8))
    }
  }

  @Test(.timeLimit(.minutes(1))) func codecUsesV4TemporalDistributionAttemptAndSelectionKeys() throws {
    let artifact = TrainingRunWorkerLaunchArtifact(
      launchID: UUID(uuidString: "63F23951-FD1E-4F84-A0BD-E675CE59E146")!,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      operation: .start(
        Self.makeRequest(
          runID: TrainingRunID("worker-v4-shape"),
          artifactRoot: URL(fileURLWithPath: "/tmp/worker-v4-shape", isDirectory: true)
        )
      )
    )

    let codec = TrainingRunWorkerLaunchArtifactCodec()
    let data = try codec.encode(artifact)
    let text = try #require(String(data: data, encoding: .utf8))
    let decoded = try codec.decode(data)

    #expect(decoded.sourceVersion == .v4)
    #expect(decoded.artifact == artifact)
    #expect(text.contains("\"schemaVersion\" : 4"))
    #expect(text.contains("\"executionMode\" : \"fixed-window-zero-recurrent-state\""))
    #expect(text.contains("\"paddingRule\" : \"zero\""))
    #expect(text.contains("\"previousActionRule\" : \"zero-before-first-decision\""))
    #expect(text.contains("\"attemptID\""))
    #expect(text.contains("\"densityContractID\""))
    #expect(text.contains("\"baseLogStandardDeviations\""))
    #expect(text.contains("\"artifactRoot\" : \"/tmp/worker-v4-shape\""))
    #expect(text.contains("\"searchScenarioSelection\""))
    #expect(text.contains("\"acceptanceScenarioSelection\""))
    #expect(text.contains("\"path\""))
    #expect(!text.contains("\"url\""))
  }

  @Test(.timeLimit(.minutes(1))) func storeRoundTripsCheckpointResumeRequest() throws {
    let launchRoot = Self.temporaryDirectory("worker-launch-resume")
    let artifactRoot = Self.temporaryDirectory("worker-artifacts-resume")
    let checkpointRoot = Self.temporaryDirectory("worker-checkpoint-resume")
    let base = Self.makeRequest(
      runID: TrainingRunID("worker-resume"),
      artifactRoot: artifactRoot
    )
    let resume = TrainingResumeRequest(
      runID: base.runID,
      source: .checkpoint(
        ModelBundleReference(
          bundleID: "resume-source",
          kind: .incumbent,
          url: checkpointRoot,
          contentHash: String(repeating: "a", count: 64)
        )),
      destinationArtifactRoot: base.artifactRoot,
      taskProfileID: base.taskProfileID,
      policyContract: base.policyContract,
      actionContract: base.actionContract,
      seedCount: base.seedCount,
      populationSize: base.populationSize,
      generationLimit: base.generationLimit,
      configuration: base.configuration
    )
    let artifact = TrainingRunWorkerLaunchArtifact(operation: .resume(resume))
    let store = TrainingRunWorkerLaunchArtifactStore(rootDirectory: launchRoot)

    let receipt = try store.write(artifact)
    let reloaded = try store.validatedArtifact(
      launchID: artifact.launchID,
      expectedSHA256Digest: receipt.sha256Digest.uppercased()
    )

    #expect(reloaded == artifact)
  }

  @Test(.timeLimit(.minutes(1))) func storeRoundTripsPinnedContinuationResumeRequest() throws {
    let launchRoot = Self.temporaryDirectory("worker-launch-continuation")
    let artifactRoot = Self.temporaryDirectory("worker-artifacts-continuation")
    let previousArtifactRoot = Self.temporaryDirectory("worker-previous-continuation")
    let checkpointRoot = previousArtifactRoot.appendingPathComponent(
      "accepted-checkpoint",
      isDirectory: true
    )
    let base = Self.makeRequest(
      runID: TrainingRunID("worker-continuation"),
      artifactRoot: artifactRoot
    )
    let resume = TrainingResumeRequest(
      runID: base.runID,
      source: .continuation(
        TrainingContinuationResumeSource(
          artifactRoot: previousArtifactRoot,
          checkpoint: ModelBundleReference(
            bundleID: "continuation-source",
            kind: .incumbent,
            url: checkpointRoot,
            contentHash: String(repeating: "c", count: 64)
          )
        )
      ),
      destinationArtifactRoot: base.artifactRoot,
      taskProfileID: base.taskProfileID,
      policyContract: base.policyContract,
      actionContract: base.actionContract,
      seedCount: base.seedCount,
      populationSize: base.populationSize,
      generationLimit: base.generationLimit,
      configuration: base.configuration
    )
    let artifact = TrainingRunWorkerLaunchArtifact(operation: .resume(resume))
    let store = TrainingRunWorkerLaunchArtifactStore(rootDirectory: launchRoot)

    let receipt = try store.write(artifact)
    let reloaded = try store.validatedArtifact(
      launchID: artifact.launchID,
      expectedSHA256Digest: receipt.sha256Digest
    )

    #expect(reloaded == artifact)
  }

  @Test(.timeLimit(.minutes(1))) func storeRejectsTamperedLaunchBytes() throws {
    let launchRoot = Self.temporaryDirectory("worker-launch-tamper")
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        Self.makeRequest(
          runID: TrainingRunID("worker-tamper"),
          artifactRoot: Self.temporaryDirectory("worker-artifacts-tamper")
        )))
    let store = TrainingRunWorkerLaunchArtifactStore(rootDirectory: launchRoot)
    let receipt = try store.write(artifact)
    var data = try Data(contentsOf: receipt.fileURL)
    data.append(Data("\n".utf8))
    try data.write(to: receipt.fileURL, options: [.atomic])

    #expect(throws: TrainingRunWorkerLaunchArtifactStore.StoreError.self) {
      _ = try store.validatedArtifact(
        launchID: artifact.launchID,
        expectedSHA256Digest: receipt.sha256Digest
      )
    }
    do {
      _ = try store.validatedArtifact(
        launchID: artifact.launchID,
        expectedSHA256Digest: receipt.sha256Digest
      )
      Issue.record("Expected the launch digest mismatch to fail closed.")
    } catch let error as TrainingRunWorkerLaunchArtifactStore.StoreError {
      guard case .digestMismatch(let expected, let actual) = error else {
        Issue.record("Unexpected store error: \(error)")
        return
      }
      #expect(expected == receipt.sha256Digest)
      #expect(actual != expected)
    }
  }

  @Test(.timeLimit(.minutes(1))) func storeKeepsLaunchArtifactsImmutable() throws {
    let launchRoot = Self.temporaryDirectory("worker-launch-immutable")
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        Self.makeRequest(
          runID: TrainingRunID("worker-immutable"),
          artifactRoot: Self.temporaryDirectory("worker-artifacts-immutable")
        )))
    let store = TrainingRunWorkerLaunchArtifactStore(rootDirectory: launchRoot)
    _ = try store.write(artifact)

    #expect(
      throws: TrainingRunWorkerLaunchArtifactStore.StoreError
        .launchAlreadyExists(artifact.launchID)
    ) {
      _ = try store.write(artifact)
    }
  }

  @Test(.timeLimit(.minutes(1))) func storeRejectsBroadLaunchArtifactPermissions() throws {
    let launchRoot = Self.temporaryDirectory("worker-launch-permissions")
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        Self.makeRequest(
          runID: TrainingRunID("worker-permissions"),
          artifactRoot: Self.temporaryDirectory("worker-artifacts-permissions")
        )))
    let store = TrainingRunWorkerLaunchArtifactStore(rootDirectory: launchRoot)
    let receipt = try store.write(artifact)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: receipt.fileURL.path
    )

    #expect(throws: TrainingRunWorkerLaunchArtifactStore.StoreError.self) {
      _ = try store.validatedArtifact(
        launchID: artifact.launchID,
        expectedSHA256Digest: receipt.sha256Digest
      )
    }
  }

  @Test(.timeLimit(.minutes(1))) func storeRejectsOversizedLaunchArtifact() throws {
    let launchRoot = Self.temporaryDirectory("worker-launch-size")
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        Self.makeRequest(
          runID: TrainingRunID("worker-size"),
          artifactRoot: Self.temporaryDirectory("worker-artifacts-size")
        )))
    let store = TrainingRunWorkerLaunchArtifactStore(rootDirectory: launchRoot)
    let receipt = try store.write(artifact)
    let oversized = Data(
      repeating: 0x20,
      count: Int(TrainingRunWorkerLaunchArtifactStore.maximumArtifactByteCount + 1)
    )
    try oversized.write(to: receipt.fileURL, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: receipt.fileURL.path
    )

    #expect(throws: TrainingRunWorkerLaunchArtifactStore.StoreError.self) {
      _ = try store.validatedArtifact(
        launchID: artifact.launchID,
        expectedSHA256Digest: receipt.sha256Digest
      )
    }
  }

  @Test(.timeLimit(.minutes(1))) func validatorRejectsUnsafeRunIdentity() {
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        Self.makeRequest(
          runID: TrainingRunID("../other-run"),
          artifactRoot: Self.temporaryDirectory("worker-artifacts-unsafe-id")
        )))

    #expect(
      throws: TrainingRunWorkerLaunchArtifactValidator.ValidationError
        .unsafeRunID("../other-run")
    ) {
      try TrainingRunWorkerLaunchArtifactValidator().validate(artifact)
    }
  }

  @Test(.timeLimit(.minutes(1))) func validatorRejectsExternalStopSentinel() {
    let artifactRoot = Self.temporaryDirectory("worker-artifacts-stop")
    let configuration = TrainingRunConfiguration(
      artifacts: TrainingArtifactPolicy(
        stopSentinelPath: Self.temporaryDirectory("external-stop")
          .appendingPathComponent("STOP", isDirectory: false)
          .path
      )
    )
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        Self.makeRequest(
          runID: TrainingRunID("worker-stop"),
          artifactRoot: artifactRoot,
          configuration: configuration
        )))

    #expect(throws: TrainingRunWorkerLaunchArtifactValidator.ValidationError.self) {
      try TrainingRunWorkerLaunchArtifactValidator().validate(artifact)
    }
  }

  @Test(.timeLimit(.minutes(1))) func storeRejectsSymbolicLinkRoot() throws {
    let actualRoot = Self.temporaryDirectory("worker-launch-actual")
    try FileManager.default.createDirectory(
      at: actualRoot,
      withIntermediateDirectories: true
    )
    let symbolicRoot = Self.temporaryDirectory("worker-launch-link")
    try FileManager.default.createSymbolicLink(
      at: symbolicRoot,
      withDestinationURL: actualRoot
    )
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        Self.makeRequest(
          runID: TrainingRunID("worker-symbolic-root"),
          artifactRoot: Self.temporaryDirectory("worker-artifacts-symbolic-root")
        )))

    #expect(
      throws: TrainingRunWorkerLaunchArtifactStore.StoreError
        .unsafeSymbolicLink(path: symbolicRoot.path)
    ) {
      _ = try TrainingRunWorkerLaunchArtifactStore(rootDirectory: symbolicRoot)
        .write(artifact)
    }
  }

  @Test(.timeLimit(.minutes(1))) func sourceSnapshotIsolatedFromLaterSourceMutation() throws {
    let root = Self.temporaryDirectory("worker-source-snapshot")
    let launchRoot = root.appendingPathComponent("launches", isDirectory: true)
    let artifactRoot = root.appendingPathComponent("artifacts", isDirectory: true)
    let sourceParent = root.appendingPathComponent("sources", isDirectory: true)
    let sourceRoot = sourceParent.appendingPathComponent("checkpoint", isDirectory: true)
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
    let sourceFile = sourceRoot.appendingPathComponent("model.json", isDirectory: false)
    let originalData = Data("original-model".utf8)
    try originalData.write(to: sourceFile)
    let source = try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [sourceParent]
    ).pinnedReference(
      ModelBundleReference(bundleID: "snapshot-source", kind: .source, url: sourceRoot)
    )
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        TrainingRunRequest(
          runID: TrainingRunID("source-snapshot"),
          artifactRoot: artifactRoot,
          taskProfileID: "lift",
          policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
          actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
          sourceBundle: source
        )
      )
    )
    let receipt = try TrainingRunWorkerLaunchArtifactStore(rootDirectory: launchRoot)
      .write(artifact) { launchDirectory in
        try TrainingRunWorkerSourceSnapshotStore().materializedArtifact(
          artifact,
          in: launchDirectory
        )
      }

    try Data("mutated-model".utf8).write(to: sourceFile)
    guard case .start(let materializedRequest) = receipt.artifact.operation else {
      Issue.record("Expected a materialized start request")
      return
    }
    let snapshot = try #require(materializedRequest.sourceBundle)
    #expect(snapshot.url != sourceRoot)
    #expect(snapshot.provenanceURL == sourceRoot)
    #expect(
      try Data(contentsOf: snapshot.url.appendingPathComponent("model.json"))
        == originalData
    )
    try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [snapshot.url.deletingLastPathComponent()]
    ).verify(receipt.artifact)

    let decoded = try TrainingRunWorkerLaunchArtifactCodec().decode(
      Data(contentsOf: receipt.fileURL)
    )
    guard case .start(let decodedRequest) = decoded.artifact.operation else {
      Issue.record("Expected a decoded start request")
      return
    }
    #expect(decodedRequest.sourceBundle?.provenanceURL == sourceRoot)
  }

  @Test(.timeLimit(.minutes(1))) func sourceSnapshotFallsBackToCopyAcrossVolumes() throws {
    let root = Self.temporaryDirectory("worker-source-copy-fallback")
    let launchRoot = root.appendingPathComponent("launches", isDirectory: true)
    let artifactRoot = root.appendingPathComponent("artifacts", isDirectory: true)
    let sourceParent = root.appendingPathComponent("sources", isDirectory: true)
    let sourceRoot = sourceParent.appendingPathComponent("checkpoint", isDirectory: true)
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
    let expected = Data("copy-fallback-model".utf8)
    try expected.write(to: sourceRoot.appendingPathComponent("model.json", isDirectory: false))
    let source = try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [sourceParent]
    ).pinnedReference(
      ModelBundleReference(bundleID: "copy-fallback", kind: .source, url: sourceRoot)
    )
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        TrainingRunRequest(
          runID: TrainingRunID("copy-fallback"),
          artifactRoot: artifactRoot,
          taskProfileID: "lift",
          policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
          actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
          sourceBundle: source
        )
      )
    )

    let receipt = try TrainingRunWorkerLaunchArtifactStore(rootDirectory: launchRoot)
      .write(artifact) { launchDirectory in
        try TrainingRunWorkerSourceSnapshotStore(
          cloner: CrossVolumeSnapshotCloner()
        ).materializedArtifact(artifact, in: launchDirectory)
      }

    guard case .start(let request) = receipt.artifact.operation else {
      Issue.record("Expected a materialized start request")
      return
    }
    let snapshot = try #require(request.sourceBundle)
    #expect(
      try Data(contentsOf: snapshot.url.appendingPathComponent("model.json")) == expected
    )
    try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [snapshot.url.deletingLastPathComponent()]
    ).verify(receipt.artifact)
  }

  @Test(.timeLimit(.minutes(1))) func durableSourceSnapshotSurvivesEphemeralSourceRemoval() throws {
    let root = Self.temporaryDirectory("worker-durable-source")
    let artifactRoot = root.appendingPathComponent("artifacts", isDirectory: true)
    let ephemeralRoot = root.appendingPathComponent("launch-cache", isDirectory: true)
    let sourceRoot = ephemeralRoot.appendingPathComponent("SOURCE_SNAPSHOT", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
    let expected = Data("durable-model".utf8)
    try expected.write(
      to: sourceRoot.appendingPathComponent("model.json", isDirectory: false)
    )
    let source = try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [ephemeralRoot]
    ).pinnedReference(
      ModelBundleReference(bundleID: "durable-source", kind: .source, url: sourceRoot)
    )
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        TrainingRunRequest(
          runID: TrainingRunID("durable-source"),
          artifactRoot: artifactRoot,
          taskProfileID: "lift",
          policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
          actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
          sourceBundle: source
        )
      )
    )

    let durableArtifact = try TrainingRunWorkerSourceSnapshotStore()
      .durableArtifact(artifact)
    guard case .start(let request) = durableArtifact.operation else {
      Issue.record("Expected a durable start request")
      return
    }
    let durableSource = try #require(request.sourceBundle)
    let expectedDurableRoot = artifactRoot
      .appendingPathComponent(
        TrainingRunWorkerSourceSnapshotStore.continuationDirectoryName,
        isDirectory: true
      )
      .appendingPathComponent(
        TrainingRunWorkerSourceSnapshotStore.snapshotDirectoryName,
        isDirectory: true
      )
    #expect(durableSource.url == expectedDurableRoot)
    #expect(durableSource.provenanceURL == sourceRoot)

    try FileManager.default.removeItem(at: ephemeralRoot)

    #expect(
      try Data(contentsOf: durableSource.url.appendingPathComponent("model.json"))
        == expected
    )
    let reusedArtifact = try TrainingRunWorkerSourceSnapshotStore()
      .durableArtifact(artifact)
    guard case .start(let reusedRequest) = reusedArtifact.operation else {
      Issue.record("Expected a reused durable start request")
      return
    }
    #expect(reusedRequest.sourceBundle?.url == expectedDurableRoot)
    try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [artifactRoot]
    ).verify(reusedArtifact)
  }

  @Test(.timeLimit(.minutes(1))) func durableSourceFailureRemovesPartialContinuation() throws {
    let root = Self.temporaryDirectory("worker-durable-source-failure")
    let artifactRoot = root.appendingPathComponent("artifacts", isDirectory: true)
    let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
    try Data("invalid-digest".utf8).write(
      to: sourceRoot.appendingPathComponent("model.json", isDirectory: false)
    )
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        TrainingRunRequest(
          runID: TrainingRunID("durable-source-failure"),
          artifactRoot: artifactRoot,
          taskProfileID: "lift",
          policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
          actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
          sourceBundle: ModelBundleReference(
            bundleID: "durable-source-failure",
            kind: .source,
            url: sourceRoot,
            contentHash: String(repeating: "0", count: 64)
          )
        )
      )
    )

    #expect(throws: TrainingRunWorkerSourceSnapshotStore.SnapshotError.self) {
      _ = try TrainingRunWorkerSourceSnapshotStore().durableArtifact(artifact)
    }
    let continuationRoot = artifactRoot.appendingPathComponent(
      TrainingRunWorkerSourceSnapshotStore.continuationDirectoryName,
      isDirectory: true
    )
    #expect(!FileManager.default.fileExists(atPath: continuationRoot.path))
  }

  @Test(.timeLimit(.minutes(1))) func durableSourceReusesAnArtifactOwnedResumeCheckpoint() throws {
    let root = Self.temporaryDirectory("worker-artifact-owned-resume")
    let artifactRoot = root.appendingPathComponent("artifacts", isDirectory: true)
    let externalSource = root.appendingPathComponent("external-source", isDirectory: true)
    try FileManager.default.createDirectory(at: externalSource, withIntermediateDirectories: true)
    try Data("initial-model".utf8).write(
      to: externalSource.appendingPathComponent("model.json", isDirectory: false)
    )
    let initialReference = try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [root]
    ).pinnedReference(
      ModelBundleReference(bundleID: "initial-source", kind: .source, url: externalSource)
    )
    let runID = TrainingRunID("artifact-owned-resume")
    let policyContract = ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract()
    let actionContract = ReferenceQuadrotorLearningContracts.bodyRateActionContract()
    let initialArtifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        TrainingRunRequest(
          runID: runID,
          artifactRoot: artifactRoot,
          taskProfileID: "lift",
          policyContract: policyContract,
          actionContract: actionContract,
          sourceBundle: initialReference
        )
      )
    )
    _ = try TrainingRunWorkerSourceSnapshotStore().durableArtifact(initialArtifact)

    let candidateRoot = artifactRoot
      .appendingPathComponent("seeds", isDirectory: true)
      .appendingPathComponent("candidate", isDirectory: true)
    try FileManager.default.createDirectory(at: candidateRoot, withIntermediateDirectories: true)
    try Data("candidate-model".utf8).write(
      to: candidateRoot.appendingPathComponent("model.json", isDirectory: false)
    )
    let candidateReference = try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [artifactRoot]
    ).pinnedReference(
      ModelBundleReference(
        bundleID: "candidate-source",
        kind: .incumbent,
        url: candidateRoot
      )
    )
    let resumeArtifact = TrainingRunWorkerLaunchArtifact(
      operation: .resume(
        TrainingResumeRequest(
          runID: runID,
          source: .checkpoint(candidateReference),
          destinationArtifactRoot: artifactRoot,
          taskProfileID: "lift",
          policyContract: policyContract,
          actionContract: actionContract
        )
      )
    )
    let launchTransportRoot = root.appendingPathComponent(
      "launch-transport",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: launchTransportRoot,
      withIntermediateDirectories: true
    )
    let transportedResume = try TrainingRunWorkerSourceSnapshotStore()
      .materializedArtifact(resumeArtifact, in: launchTransportRoot)

    let durableResume = try TrainingRunWorkerSourceSnapshotStore()
      .durableArtifact(transportedResume)
    guard case .resume(let request) = durableResume.operation,
      case .checkpoint(let retainedCandidate) = request.source
    else {
      Issue.record("Expected an artifact-owned resume checkpoint")
      return
    }
    #expect(retainedCandidate.url == candidateRoot)
    #expect(
      try Data(contentsOf: retainedCandidate.url.appendingPathComponent("model.json"))
        == Data("candidate-model".utf8)
    )
    let initialSnapshot = artifactRoot
      .appendingPathComponent(
        TrainingRunWorkerSourceSnapshotStore.continuationDirectoryName,
        isDirectory: true
      )
      .appendingPathComponent(
        TrainingRunWorkerSourceSnapshotStore.snapshotDirectoryName,
        isDirectory: true
      )
    #expect(
      try Data(contentsOf: initialSnapshot.appendingPathComponent("model.json"))
        == Data("initial-model".utf8)
    )
  }

  @Test(.timeLimit(.minutes(1))) func snapshotFailureRemovesReadOnlyLaunchTree() throws {
    let root = Self.temporaryDirectory("worker-source-cleanup")
    let launchRoot = root.appendingPathComponent("launches", isDirectory: true)
    let artifactRoot = root.appendingPathComponent("artifacts", isDirectory: true)
    let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
    try Data("cleanup-model".utf8).write(
      to: sourceRoot.appendingPathComponent("model.json", isDirectory: false)
    )
    let artifact = TrainingRunWorkerLaunchArtifact(
      operation: .start(
        TrainingRunRequest(
          runID: TrainingRunID("snapshot-cleanup"),
          artifactRoot: artifactRoot,
          taskProfileID: "lift",
          policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
          actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
          sourceBundle: ModelBundleReference(
            bundleID: "cleanup-source",
            kind: .source,
            url: sourceRoot,
            contentHash: String(repeating: "0", count: 64)
          )
        )
      )
    )
    let store = TrainingRunWorkerLaunchArtifactStore(rootDirectory: launchRoot)

    do {
      _ = try store.write(artifact) { launchDirectory in
        try TrainingRunWorkerSourceSnapshotStore().materializedArtifact(
          artifact,
          in: launchDirectory
        )
      }
      Issue.record("Expected source digest mismatch")
    } catch let error as TrainingRunWorkerLaunchArtifactStore.StoreError {
      if case .cleanupFailed = error {
        Issue.record("Read-only snapshot prevented launch cleanup: \(error)")
      }
    }
    #expect(!FileManager.default.fileExists(atPath: store.launchDirectory(for: artifact.launchID).path))
  }

  private static func makeRequest(
    runID: TrainingRunID,
    artifactRoot: URL,
    configuration: TrainingRunConfiguration = TrainingRunConfiguration()
  ) -> TrainingRunRequest {
    TrainingRunRequest(
      runID: runID,
      artifactRoot: artifactRoot,
      taskProfileID: "lift",
      policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
      actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
      sourceBundle: ModelBundleReference(
        bundleID: "source",
        kind: .source,
        url: temporaryDirectory("worker-source-bundle"),
        contentHash: String(repeating: "b", count: 64)
      ),
      seedCount: 2,
      populationSize: 4,
      generationLimit: 10,
      configuration: configuration
    )
  }

  private static func temporaryDirectory(_ prefix: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
  }
}

private struct CrossVolumeSnapshotCloner: TrainingRunWorkerSourceSnapshotCloning {
  func clone(source: URL, destination: URL) throws {
    throw POSIXTrainingRunWorkerSourceSnapshotCloner.CloneError.failed(code: EXDEV)
  }
}

@Suite("Training run worker execution service")
struct TrainingRunWorkerExecutionServiceTests {
  @Test(.timeLimit(.minutes(1))) func serviceExecutesStartAndForwardsEvents() async throws {
    let request = Self.makeRequest(runID: TrainingRunID("worker-service-start"))
    let summary = TrainingRunSummary(
      runID: request.runID,
      artifactRoot: request.artifactRoot,
      terminalState: .completed
    )
    let executor = WorkerRecordingExecutor(summary: summary)
    let events = WorkerEventRecorder()

    let result = try await TrainingRunWorkerExecutionService(executor: executor).execute(
      TrainingRunWorkerLaunchArtifact(operation: .start(request))
    ) { event in
      await events.append(event)
    }

    #expect(result == summary)
    #expect(executor.startCount == 1)
    #expect(executor.resumeCount == 0)
    #expect(await events.values == [.iterationStarted(1)])
  }

  @Test(.timeLimit(.minutes(1))) func serviceExecutesResumeOperation() async throws {
    let request = Self.makeRequest(runID: TrainingRunID("worker-service-resume"))
    let resume = TrainingResumeRequest(
      runID: request.runID,
      source: .artifactRoot(request.artifactRoot),
      destinationArtifactRoot: request.artifactRoot,
      taskProfileID: request.taskProfileID,
      policyContract: request.policyContract,
      actionContract: request.actionContract
    )
    let summary = TrainingRunSummary(
      runID: request.runID,
      artifactRoot: request.artifactRoot,
      terminalState: .completed
    )
    let executor = WorkerRecordingExecutor(summary: summary)

    let result = try await TrainingRunWorkerExecutionService(executor: executor).execute(
      TrainingRunWorkerLaunchArtifact(operation: .resume(resume))
    )

    #expect(result == summary)
    #expect(executor.startCount == 0)
    #expect(executor.resumeCount == 1)
  }

  @Test(.timeLimit(.minutes(1))) func serviceCancellationReachesRegisteredHandle() async throws {
    let request = Self.makeRequest(runID: TrainingRunID("worker-service-cancel"))
    let handle = WorkerCancellationHandle(
      runID: request.runID,
      artifactRoot: request.artifactRoot
    )
    let executor = WorkerRecordingExecutor(handle: handle)
    let task = Task {
      try await TrainingRunWorkerExecutionService(executor: executor).execute(
        TrainingRunWorkerLaunchArtifact(operation: .start(request))
      )
    }
    try await Task.sleep(for: .milliseconds(20))

    task.cancel()
    let summary = try await task.value

    #expect(summary.terminalState == .cancelled)
    #expect(handle.cancelCount == 1)
    #expect(handle.shutdownCount == 1)
  }

  @Test(.timeLimit(.minutes(1))) func eventFailureCancelsTheTrainingHandle() async throws {
    let request = Self.makeRequest(runID: TrainingRunID("worker-service-event-failure"))
    let handle = WorkerCancellationHandle(
      runID: request.runID,
      artifactRoot: request.artifactRoot
    )
    let executor = WorkerRecordingExecutor(handle: handle)

    do {
      _ = try await TrainingRunWorkerExecutionService(executor: executor).execute(
        TrainingRunWorkerLaunchArtifact(operation: .start(request))
      ) { _ in
        throw WorkerTestError.eventPersistence
      }
      Issue.record("Expected event persistence failure to terminate execution")
    } catch WorkerTestError.eventPersistence {
    }

    #expect(handle.cancelCount == 1)
    #expect(handle.shutdownCount == 1)
  }

  private static func makeRequest(runID: TrainingRunID) -> TrainingRunRequest {
    let artifactRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent(runID.rawValue, isDirectory: true)
    return TrainingRunRequest(
      runID: runID,
      artifactRoot: artifactRoot,
      taskProfileID: "lift",
      policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
      actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract()
    )
  }
}

private actor WorkerEventRecorder {
  private(set) var values: [TrainingRunEvent] = []

  func append(_ event: TrainingRunEvent) {
    values.append(event)
  }
}

private final class WorkerRecordingExecutor: AnyTrainingRunExecuting, Sendable {
  private struct State: Sendable {
    var startCount = 0
    var resumeCount = 0
  }

  private let state = Mutex(State())
  private let handle: any TrainingRunHandle

  var startCount: Int { state.withLock { $0.startCount } }
  var resumeCount: Int { state.withLock { $0.resumeCount } }

  init(summary: TrainingRunSummary) {
    self.handle = WorkerStaticHandle(summary: summary)
  }

  init(handle: any TrainingRunHandle) {
    self.handle = handle
  }

  func start(_ request: TrainingRunRequest) async throws -> any TrainingRunHandle {
    state.withLock { $0.startCount += 1 }
    return handle
  }

  func resume(_ request: TrainingResumeRequest) async throws -> any TrainingRunHandle {
    state.withLock { $0.resumeCount += 1 }
    return handle
  }

  func continuationSelection(from artifactRoot: URL) throws -> TrainingContinuationSelection {
    throw WorkerTestError.unused
  }

  func validate(_ request: TrainingRunRequest) throws {}

  func validate(_ request: TrainingResumeRequest) throws {}
}

private final class WorkerStaticHandle: TrainingRunHandle, Sendable {
  let runID: TrainingRunID
  let progress = Progress(totalUnitCount: 1)
  let events: AsyncStream<TrainingRunEvent>

  private let summary: TrainingRunSummary

  init(summary: TrainingRunSummary) {
    self.runID = summary.runID
    self.summary = summary
    self.events = AsyncStream { continuation in
      continuation.yield(.iterationStarted(1))
      continuation.finish()
    }
  }

  func cancel() {}

  func wait() async throws -> TrainingRunSummary {
    summary
  }

  func shutdown() async {}
}

private final class WorkerCancellationHandle: TrainingRunHandle, Sendable {
  private struct State: Sendable {
    var cancelled = false
    var cancelCount = 0
    var shutdownCount = 0
  }

  let runID: TrainingRunID
  let progress = Progress(totalUnitCount: 1)
  let events: AsyncStream<TrainingRunEvent>

  private let artifactRoot: URL
  private let state = Mutex(State())
  private let continuation: AsyncStream<TrainingRunEvent>.Continuation

  var cancelCount: Int { state.withLock { $0.cancelCount } }
  var shutdownCount: Int { state.withLock { $0.shutdownCount } }

  init(runID: TrainingRunID, artifactRoot: URL) {
    self.runID = runID
    self.artifactRoot = artifactRoot
    let pipe = AsyncStream<TrainingRunEvent>.makeStream()
    self.events = pipe.stream
    self.continuation = pipe.continuation
    self.continuation.yield(.iterationStarted(1))
  }

  func cancel() {
    state.withLock { state in
      state.cancelled = true
      state.cancelCount += 1
    }
    continuation.finish()
  }

  func wait() async throws -> TrainingRunSummary {
    while !state.withLock({ $0.cancelled }) {
      do {
        try await Task.sleep(for: .milliseconds(5))
      } catch is CancellationError {
        await Task.yield()
      }
    }
    return TrainingRunSummary(
      runID: runID,
      artifactRoot: artifactRoot,
      terminalState: .cancelled,
      failureReasons: ["cancelled"]
    )
  }

  func shutdown() async {
    state.withLock { $0.shutdownCount += 1 }
    continuation.finish()
  }
}

private enum WorkerTestError: Error {
  case unused
  case eventPersistence
}
