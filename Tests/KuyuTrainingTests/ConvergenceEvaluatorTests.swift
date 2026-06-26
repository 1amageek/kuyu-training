import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import Testing
@testable import KuyuTraining

@Test func convergenceAcceptsImprovingFiniteLossAndScore() {
    let metrics = [
        metric(iteration: 1, kind: .loss, value: 1.0),
        metric(iteration: 2, kind: .loss, value: 0.85),
        metric(iteration: 3, kind: .loss, value: 0.7),
        metric(iteration: 1, kind: .score, value: 0.1),
        metric(iteration: 2, kind: .score, value: 0.2),
        metric(iteration: 3, kind: .score, value: 0.4),
    ]

    let summary = ConvergenceEvaluator(config: .init(windowSize: 3, minDelta: 0.01))
        .evaluate(runID: "run-a", metrics: metrics, bestCheckpointID: "ckpt-a")

    #expect(summary.accepted)
    #expect(summary.bestCheckpointID == "ckpt-a")
    #expect(summary.finalTrainingLoss == 0.7)
}

@Test func convergenceRejectsNonFiniteMetrics() {
    let metrics = [
        metric(iteration: 1, kind: .loss, value: 1.0),
        metric(iteration: 2, kind: .loss, value: .nan),
    ]

    let summary = ConvergenceEvaluator()
        .evaluate(runID: "run-b", metrics: metrics, bestCheckpointID: nil)

    #expect(!summary.accepted)
    #expect(summary.reason.contains("non-finite"))
}

@Test func convergenceRejectsSafetyRegressionEvenWhenRewardImproves() {
    let metrics = [
        metric(iteration: 1, kind: .rewardAverage, value: 0.1),
        metric(iteration: 2, kind: .rewardAverage, value: 0.4),
        metric(iteration: 3, kind: .rewardAverage, value: 0.9),
        metric(iteration: 4, kind: .rewardAverage, value: 1.0),
        metric(iteration: 5, kind: .rewardAverage, value: 1.1),
        metric(iteration: 6, kind: .rewardAverage, value: 1.2),
        metric(iteration: 1, kind: .safetyViolation, value: 0.0),
        metric(iteration: 2, kind: .safetyViolation, value: 0.2),
        metric(iteration: 3, kind: .safetyViolation, value: 0.5),
        metric(iteration: 4, kind: .safetyViolation, value: 0.8),
        metric(iteration: 5, kind: .safetyViolation, value: 1.1),
        metric(iteration: 6, kind: .safetyViolation, value: 1.4),
    ]

    let summary = ConvergenceEvaluator(config: .init(windowSize: 3, minDelta: 0.01))
        .evaluate(runID: "run-c", metrics: metrics, bestCheckpointID: "ckpt-c")

    #expect(!summary.accepted)
    #expect(summary.safetyRegressionDetected)
}

@Test func convergenceDetectsPlateauWithDefaultWindow() {
    let metrics = [
        metric(iteration: 1, kind: .loss, value: 1.0),
        metric(iteration: 2, kind: .loss, value: 1.0),
        metric(iteration: 3, kind: .loss, value: 1.0),
        metric(iteration: 4, kind: .loss, value: 1.0),
        metric(iteration: 5, kind: .loss, value: 1.0),
        metric(iteration: 6, kind: .loss, value: 1.0),
    ]

    let summary = ConvergenceEvaluator(config: .init(windowSize: 3, minDelta: 0.01))
        .evaluate(runID: "run-d", metrics: metrics, bestCheckpointID: nil)

    #expect(!summary.accepted)
    #expect(summary.plateauDetected)
}

@Test func trainingArtifactWriterPersistsManifestMetricsAndConvergence() throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }

    let manifest = LearningRunManifest(
        runID: "run-artifact",
        mode: .supervised,
        robotManifestID: "quad",
        robotManifestHash: "robot-manifest-hash",
        configHash: "config-hash",
        suiteID: "Single Lift",
        seedSet: [1, 2],
        policyID: "manasMLX",
        parentCheckpointID: nil,
        outputCheckpointID: "ckpt-out",
        workerCount: 2,
        startedAt: Date(timeIntervalSince1970: 1),
        completedAt: Date(timeIntervalSince1970: 2),
        terminalState: .completed,
        failureReason: nil
    )
    let metrics = [
        metric(runID: "run-artifact", iteration: 1, kind: .score, value: 0.5),
        metric(runID: "run-artifact", iteration: 1, kind: .loss, value: 0.25),
    ]
    let convergence = ConvergenceSummary(
        runID: "run-artifact",
        accepted: true,
        reason: "accepted",
        bestCheckpointID: "ckpt-out",
        finalTrainingLoss: 0.25,
        finalValidationLoss: nil,
        rewardMovingAverage: nil,
        passRate: 1.0,
        failureRate: 0.0,
        safetyRegressionDetected: false,
        plateauDetected: false,
        overfitRiskDetected: false
    )
    let checkpointDecision = CheckpointDecision(
        runID: "run-artifact",
        state: .accepted,
        reason: "accepted",
        candidateCheckpointID: "ckpt-out",
        candidateCheckpointURL: directory.appendingPathComponent("candidate"),
        publishedCheckpointURL: directory.appendingPathComponent("checkpoints/accepted"),
        decidedAt: Date(timeIntervalSince1970: 3)
    )
    let scenarioRuns = [
        TrainingScenarioRunArtifact(
            runID: "run-artifact",
            iteration: 1,
            output: TrainingScenarioRunOutput(kuyAtt1: try trainingContractRunOutput(passed: true))
        )
    ]

    try TrainingArtifactWriter().write(
        manifest: manifest,
        metrics: metrics,
        convergence: convergence,
        checkpointDecision: checkpointDecision,
        scenarioRuns: scenarioRuns,
        to: directory
    )

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decodedManifest = try decoder.decode(
        LearningRunManifest.self,
        from: Data(contentsOf: directory.appendingPathComponent("manifest.json"))
    )
    let decodedConvergence = try decoder.decode(
        ConvergenceSummary.self,
        from: Data(contentsOf: directory.appendingPathComponent("convergence.json"))
    )
    let decodedDecision = try decoder.decode(
        CheckpointDecision.self,
        from: Data(contentsOf: directory.appendingPathComponent("checkpoint-decision.json"))
    )
    let metricLines = try String(
        contentsOf: directory.appendingPathComponent("metrics.jsonl"),
        encoding: .utf8
    )
    .split(separator: "\n")
    let artifactBundle = try TrainingRunArtifactValidator().loadAndValidate(from: directory)

    #expect(decodedManifest.runID == manifest.runID)
    #expect(decodedConvergence.accepted)
    #expect(decodedDecision.state == .accepted)
    #expect(metricLines.count == metrics.count)
    #expect(artifactBundle.contract.schemaVersion == TrainingRunArtifactContract.currentSchemaVersion)
    #expect(artifactBundle.manifest.runID == manifest.runID)
    #expect(artifactBundle.metrics.count == metrics.count)
    #expect(artifactBundle.scenarioRuns.count == scenarioRuns.count)
}

@Test func trainingRunArtifactValidatorRejectsRunIDMismatch() throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }

    let manifest = LearningRunManifest(
        runID: "run-artifact",
        mode: .supervised,
        configHash: "config-hash",
        suiteID: "Single Lift",
        seedSet: [1],
        policyID: "manasMLX",
        outputCheckpointID: nil,
        workerCount: 1,
        startedAt: Date(timeIntervalSince1970: 1),
        completedAt: Date(timeIntervalSince1970: 2),
        terminalState: .rejected,
        failureReason: "failed"
    )
    let convergence = ConvergenceSummary(
        runID: "other-run",
        accepted: false,
        reason: "failed",
        passRate: 0.0,
        failureRate: 1.0,
        safetyRegressionDetected: false,
        plateauDetected: false,
        overfitRiskDetected: false
    )
    let checkpointDecision = CheckpointDecision(
        runID: "run-artifact",
        state: .skipped,
        reason: "failed",
        candidateCheckpointID: nil,
        candidateCheckpointURL: nil,
        publishedCheckpointURL: nil,
        decidedAt: Date(timeIntervalSince1970: 3)
    )

    try TrainingArtifactWriter().write(
        manifest: manifest,
        metrics: [metric(runID: "run-artifact", iteration: 1, kind: .score, value: 0.1)],
        convergence: convergence,
        checkpointDecision: checkpointDecision,
        to: directory
    )

    do {
        _ = try TrainingRunArtifactValidator().loadAndValidate(from: directory)
        Issue.record("Expected artifact validator to reject mismatched run IDs")
    } catch let error as TrainingRunArtifactValidator.ValidationError {
        #expect(error == .runIDMismatch(file: "convergence.json", expected: "run-artifact", actual: "other-run"))
    }
}

@Test func trainingRunArtifactValidatorRejectsPartialWorkerMetricIdentity() throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }

    let manifest = LearningRunManifest(
        runID: "run-worker-metric",
        mode: .rlRollout,
        configHash: "config-hash",
        suiteID: "Lift",
        seedSet: [1],
        policyID: "manasMLX",
        outputCheckpointID: nil,
        workerCount: 2,
        startedAt: Date(timeIntervalSince1970: 1),
        completedAt: Date(timeIntervalSince1970: 2),
        terminalState: .failed,
        failureReason: "worker-metric-invalid"
    )
    let convergence = ConvergenceSummary(
        runID: "run-worker-metric",
        accepted: false,
        reason: "worker-metric-invalid",
        passRate: 0.0,
        failureRate: 1.0,
        safetyRegressionDetected: false,
        plateauDetected: false,
        overfitRiskDetected: false
    )
    let checkpointDecision = CheckpointDecision(
        runID: "run-worker-metric",
        state: .skipped,
        reason: "no-candidate",
        candidateCheckpointID: nil,
        candidateCheckpointURL: nil,
        publishedCheckpointURL: nil,
        decidedAt: Date(timeIntervalSince1970: 3)
    )
    let metrics = [
        TrainingMetricRecord(
            runID: "run-worker-metric",
            iteration: 1,
            kind: .workerThroughput,
            value: 10,
            workerIndex: 0
        )
    ]

    try TrainingArtifactWriter().write(
        manifest: manifest,
        metrics: metrics,
        convergence: convergence,
        checkpointDecision: checkpointDecision,
        to: directory
    )

    do {
        _ = try TrainingRunArtifactValidator().loadAndValidate(from: directory)
        Issue.record("Expected partial worker metric identity to fail closed.")
    } catch let error as TrainingRunArtifactValidator.ValidationError {
        #expect(error == .invalidWorkerMetric(kind: .workerThroughput, iteration: 1))
    }
}

@Test func trainingRunArtifactValidatorRejectsAcceptedConvergenceWithoutAcceptedCheckpointDecision() throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }

    try writeTrainingRunArtifact(
        to: directory,
        convergenceAccepted: true,
        checkpointState: .skipped,
        candidateCheckpointID: nil,
        candidateCheckpointURL: nil,
        publishedCheckpointURL: nil,
        outputCheckpointID: nil
    )

    do {
        _ = try TrainingRunArtifactValidator().loadAndValidate(from: directory)
        Issue.record("Expected accepted convergence with skipped checkpoint decision to fail closed.")
    } catch let error as TrainingRunArtifactValidator.ValidationError {
        #expect(error == .checkpointDecisionConvergenceMismatch(state: .skipped, accepted: true))
    }
}

@Test func trainingRunArtifactValidatorRejectsAcceptedCheckpointDecisionWithoutAcceptedConvergence() throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }
    let candidate = directory.appendingPathComponent("candidate", isDirectory: true)
    let published = directory.appendingPathComponent("checkpoints/accepted", isDirectory: true)

    try writeTrainingRunArtifact(
        to: directory,
        convergenceAccepted: false,
        checkpointState: .accepted,
        candidateCheckpointID: "ckpt-out",
        candidateCheckpointURL: candidate,
        publishedCheckpointURL: published,
        outputCheckpointID: "ckpt-out"
    )

    do {
        _ = try TrainingRunArtifactValidator().loadAndValidate(from: directory)
        Issue.record("Expected accepted checkpoint decision without accepted convergence to fail closed.")
    } catch let error as TrainingRunArtifactValidator.ValidationError {
        #expect(error == .checkpointDecisionConvergenceMismatch(state: .accepted, accepted: false))
    }
}

@Test func trainingRunArtifactValidatorRejectsAcceptedCheckpointWithoutPublishedEvidence() throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }
    let candidate = directory.appendingPathComponent("candidate", isDirectory: true)

    try writeTrainingRunArtifact(
        to: directory,
        convergenceAccepted: true,
        checkpointState: .accepted,
        candidateCheckpointID: "ckpt-out",
        candidateCheckpointURL: candidate,
        publishedCheckpointURL: nil,
        outputCheckpointID: "ckpt-out"
    )

    do {
        _ = try TrainingRunArtifactValidator().loadAndValidate(from: directory)
        Issue.record("Expected accepted checkpoint without published evidence to fail closed.")
    } catch let error as TrainingRunArtifactValidator.ValidationError {
        #expect(error == .acceptedCheckpointMissingPublishedURL)
    }
}

@Test func trainingRunArtifactValidatorRejectsStagedCheckpointWithoutCandidateEvidence() throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }

    try writeTrainingRunArtifact(
        to: directory,
        convergenceAccepted: true,
        checkpointState: .staged,
        candidateCheckpointID: "ckpt-out",
        candidateCheckpointURL: nil,
        publishedCheckpointURL: nil,
        outputCheckpointID: "ckpt-out"
    )

    do {
        _ = try TrainingRunArtifactValidator().loadAndValidate(from: directory)
        Issue.record("Expected staged checkpoint without candidate URL to fail closed.")
    } catch let error as TrainingRunArtifactValidator.ValidationError {
        #expect(error == .stagedCheckpointMissingCandidateURL)
    }
}

@Test func trainingRunArtifactValidatorRejectsAcceptedCheckpointIDMismatch() throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }
    let candidate = directory.appendingPathComponent("candidate", isDirectory: true)
    let published = directory.appendingPathComponent("checkpoints/accepted", isDirectory: true)

    try writeTrainingRunArtifact(
        to: directory,
        convergenceAccepted: true,
        checkpointState: .accepted,
        candidateCheckpointID: "ckpt-decision",
        candidateCheckpointURL: candidate,
        publishedCheckpointURL: published,
        outputCheckpointID: "ckpt-manifest"
    )

    do {
        _ = try TrainingRunArtifactValidator().loadAndValidate(from: directory)
        Issue.record("Expected accepted checkpoint with mismatched manifest output ID to fail closed.")
    } catch let error as TrainingRunArtifactValidator.ValidationError {
        #expect(error == .outputCheckpointMismatch(expected: "ckpt-decision", actual: "ckpt-manifest"))
    }
}

@Test func trainingRunArtifactValidatorRejectsCompletedManifestWithoutAcceptedConvergence() throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }

    try writeTrainingRunArtifact(
        to: directory,
        convergenceAccepted: false,
        checkpointState: .skipped,
        candidateCheckpointID: nil,
        candidateCheckpointURL: nil,
        publishedCheckpointURL: nil,
        outputCheckpointID: nil,
        terminalState: .completed
    )

    do {
        _ = try TrainingRunArtifactValidator().loadAndValidate(from: directory)
        Issue.record("Expected completed manifest without accepted convergence to fail closed.")
    } catch let error as TrainingRunArtifactValidator.ValidationError {
        #expect(error == .manifestConvergenceMismatch(state: .completed, accepted: false))
    }
}

@Test func trainingRunArtifactValidatorRejectsRejectedManifestWithOutputCheckpoint() throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }

    try writeTrainingRunArtifact(
        to: directory,
        convergenceAccepted: false,
        checkpointState: .skipped,
        candidateCheckpointID: nil,
        candidateCheckpointURL: nil,
        publishedCheckpointURL: nil,
        outputCheckpointID: "stale-output"
    )

    do {
        _ = try TrainingRunArtifactValidator().loadAndValidate(from: directory)
        Issue.record("Expected rejected manifest with output checkpoint to fail closed.")
    } catch let error as TrainingRunArtifactValidator.ValidationError {
        #expect(error == .unexpectedOutputCheckpointID(state: .skipped, outputCheckpointID: "stale-output"))
    }
}

@Test func trainingRunArtifactValidatorRejectsTerminalManifestWithoutCompletionTime() throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }

    try writeTrainingRunArtifact(
        to: directory,
        convergenceAccepted: false,
        checkpointState: .skipped,
        candidateCheckpointID: nil,
        candidateCheckpointURL: nil,
        publishedCheckpointURL: nil,
        outputCheckpointID: nil,
        completedAt: nil
    )

    do {
        _ = try TrainingRunArtifactValidator().loadAndValidate(from: directory)
        Issue.record("Expected terminal manifest without completion time to fail closed.")
    } catch let error as TrainingRunArtifactValidator.ValidationError {
        #expect(error == .missingTerminalCompletionTime(.rejected))
    }
}

@MainActor
@Test func TrainingRunOrchestratorWritesArtifactsForSuccessfulRun() async throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }
    let candidate = directory.appendingPathComponent("candidate", isDirectory: true)
    try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
    try Data("candidate".utf8).write(to: candidate.appendingPathComponent("model.json"))
    let executor = FakeTrainingScenarioExecutor(output: try trainingContractRunOutput(passed: true))
    let backend = FakeTrainingBackend(result: TrainingBackendResult(
        finalLoss: 0.2,
        epochs: 1,
        candidateCheckpointID: "ckpt-success",
        candidateCheckpointURL: candidate
    ))
    let orchestrator = TrainingRunOrchestrator(scenarioExecutor: executor, backend: backend)

    let result = await orchestrator.run(
        config: TrainingRunConfig(
            runID: "run-success",
            mode: .supervised,
            maxIterations: 1,
            minDelta: 0.01,
            enableDatasetExport: true,
            enableTraining: true,
            policyID: "manasMLX"
        ),
        runRequest: try trainingContractRunRequest(),
        trainingTemplate: TrainingBackendRequest(
            datasetURL: directory,
            sequenceLength: 2,
            epochs: 1,
            learningRate: 0.001,
            useAux: false,
            useQualityGating: true,
            maxBatches: 1
        ),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .completed)
    #expect(result.convergence.accepted)
    #expect(result.checkpointDecision.state == .accepted)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("checkpoints/accepted/model.json").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("metrics.jsonl").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("convergence.json").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("checkpoint-decision.json").path))
}

@MainActor
@Test func TrainingRunOrchestratorMixesAdditionalDatasetsBeforeBackendTraining() async throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }
    let output = try trainingContractRunOutput(passed: true)
    let extraDatasetRoot = directory.appendingPathComponent("extra-datasets", isDirectory: true)
    _ = try TrainingDatasetExporter().write(output: output, to: extraDatasetRoot)
    let executor = FakeTrainingScenarioExecutor(output: output)
    let backend = FakeTrainingBackend(result: TrainingBackendResult(finalLoss: 0.2, epochs: 1))
    let orchestrator = TrainingRunOrchestrator(scenarioExecutor: executor, backend: backend)

    _ = await orchestrator.run(
        config: TrainingRunConfig(
            runID: "run-mixed-datasets",
            mode: .supervised,
            maxIterations: 1,
            minDelta: 0.01,
            enableDatasetExport: true,
            enableTraining: true,
            policyID: "manasMLX"
        ),
        runRequest: try trainingContractRunRequest(),
        trainingTemplate: TrainingBackendRequest(
            datasetURL: directory,
            additionalDatasetURLs: [extraDatasetRoot],
            additionalDatasetRepeatCount: 2,
            sequenceLength: 2,
            epochs: 1,
            learningRate: 0.001,
            useAux: false,
            useQualityGating: true,
            maxBatches: 1,
            miniBatchSize: 64
        ),
        artifactDirectory: directory.appendingPathComponent("run", isDirectory: true)
    )

    let request = try #require(backend.requests.first)
    #expect(request.datasetURL.lastPathComponent == "iter-1-mixed")
    #expect(request.miniBatchSize == 64)
    let manifestData = try Data(contentsOf: request.datasetURL.appendingPathComponent("dataset-mix-manifest.json"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let manifest = try decoder.decode(TrainingDatasetMixManifest.self, from: manifestData)
    #expect(manifest.datasetCount == 3)
    #expect(manifest.sources.count == 3)
    #expect(manifest.sources.first?.path == extraDatasetRoot.path)
    #expect(manifest.sources.dropFirst().first?.path == extraDatasetRoot.path)
}

@MainActor
@Test func TrainingRunOrchestratorRejectsAdditionalDatasetsWithoutTerminalFacts() async throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }
    let output = try trainingContractRunOutput(passed: true)
    let invalidDataset = directory.appendingPathComponent("invalid-extra-dataset", isDirectory: true)
    try writeTrainingContractDatasetWithoutTerminalFacts(to: invalidDataset)
    let executor = FakeTrainingScenarioExecutor(output: output)
    let backend = FakeTrainingBackend(result: TrainingBackendResult(finalLoss: 0.2, epochs: 1))
    let orchestrator = TrainingRunOrchestrator(scenarioExecutor: executor, backend: backend)

    let result = await orchestrator.run(
        config: TrainingRunConfig(
            runID: "run-invalid-additional-dataset",
            mode: .supervised,
            maxIterations: 1,
            minDelta: 0.01,
            enableDatasetExport: true,
            enableTraining: true,
            policyID: "manasMLX"
        ),
        runRequest: try trainingContractRunRequest(),
        trainingTemplate: TrainingBackendRequest(
            datasetURL: directory,
            additionalDatasetURLs: [invalidDataset],
            sequenceLength: 2,
            epochs: 1,
            learningRate: 0.001,
            useAux: false,
            useQualityGating: true,
            maxBatches: 1
        ),
        artifactDirectory: directory.appendingPathComponent("run", isDirectory: true)
    )

    #expect(result.manifest.terminalState == .failed)
    #expect(result.manifest.failureReason?.contains("datasetContractViolation") == true)
    #expect(backend.requests.isEmpty)
}

@MainActor
@Test func TrainingRunOrchestratorRejectsBackendFailureWithoutPublishingCandidate() async throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }
    let executor = FakeTrainingScenarioExecutor(output: try trainingContractRunOutput(passed: true))
    let backend = FailingTrainingBackend()
    let orchestrator = TrainingRunOrchestrator(scenarioExecutor: executor, backend: backend)

    let result = await orchestrator.run(
        config: TrainingRunConfig(
            runID: "run-backend-failure",
            mode: .supervised,
            maxIterations: 1,
            minDelta: 0.01,
            enableDatasetExport: true,
            enableTraining: true,
            policyID: "manasMLX"
        ),
        runRequest: try trainingContractRunRequest(),
        trainingTemplate: TrainingBackendRequest(
            datasetURL: directory,
            sequenceLength: 2,
            epochs: 1,
            learningRate: 0.001,
            useAux: false,
            useQualityGating: true,
            maxBatches: 1
        ),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .failed)
    #expect(!result.convergence.accepted)
    #expect(result.manifest.outputCheckpointID == nil)
    #expect(result.checkpointDecision.state == .skipped)
    #expect(result.convergence.reason.contains("backend-failed"))
}

@MainActor
@Test func TrainingRunOrchestratorReportsDatasetExportFailureBeforeTraining() async throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }
    let fileArtifactRoot = directory.appendingPathComponent("artifact-file")
    try Data("not-a-directory".utf8).write(to: fileArtifactRoot)
    let executor = FakeTrainingScenarioExecutor(output: try trainingContractRunOutput(passed: true))
    let backend = FakeTrainingBackend(result: TrainingBackendResult(
        finalLoss: 0.2,
        epochs: 1,
        candidateCheckpointID: "ckpt-should-not-exist"
    ))
    let orchestrator = TrainingRunOrchestrator(scenarioExecutor: executor, backend: backend)

    let result = await orchestrator.run(
        config: TrainingRunConfig(
            runID: "run-dataset-failure",
            mode: .supervised,
            maxIterations: 1,
            minDelta: 0.01,
            enableDatasetExport: true,
            enableTraining: true,
            policyID: "manasMLX"
        ),
        runRequest: try trainingContractRunRequest(),
        trainingTemplate: TrainingBackendRequest(
            datasetURL: directory,
            sequenceLength: 2,
            epochs: 1,
            learningRate: 0.001,
            useAux: false,
            useQualityGating: true,
            maxBatches: 1
        ),
        artifactDirectory: fileArtifactRoot
    )

    #expect(result.manifest.terminalState == .failed)
    #expect(!result.convergence.accepted)
    #expect(result.manifest.outputCheckpointID == nil)
    #expect(result.checkpointDecision.state == .skipped)
    #expect(backend.calls == 0)
}

@MainActor
@Test func checkpointRepositoryDoesNotPublishRejectedCandidateToAcceptedPath() async throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }
    let candidate = directory.appendingPathComponent("candidate", isDirectory: true)
    try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
    try Data("candidate".utf8).write(to: candidate.appendingPathComponent("model.json"))
    let executor = FakeTrainingScenarioExecutor(output: try trainingContractRunOutput(passed: false))
    let backend = FakeTrainingBackend(result: TrainingBackendResult(
        finalLoss: 1.0,
        epochs: 1,
        candidateCheckpointID: "ckpt-rejected",
        candidateCheckpointURL: candidate
    ))
    let orchestrator = TrainingRunOrchestrator(
        scenarioExecutor: executor,
        backend: backend,
        convergenceEvaluator: ConvergenceEvaluator(config: .init(windowSize: 1, minDelta: 0.01))
    )

    let result = await orchestrator.run(
        config: TrainingRunConfig(
            runID: "run-rejected-checkpoint",
            mode: .supervised,
            maxIterations: 2,
            minDelta: 0.01,
            enableDatasetExport: true,
            enableTraining: true,
            policyID: "manasMLX"
        ),
        runRequest: try trainingContractRunRequest(),
        trainingTemplate: TrainingBackendRequest(
            datasetURL: directory,
            sequenceLength: 2,
            epochs: 1,
            learningRate: 0.001,
            useAux: false,
            useQualityGating: true,
            maxBatches: 1
        ),
        artifactDirectory: directory
    )

    #expect(result.checkpointDecision.state == .rejected)
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("checkpoints/accepted/model.json").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("checkpoints/rejected/run-rejected-checkpoint").path))
}

@MainActor
@Test func TrainingRunOrchestratorChainsCandidateSnapshotIntoNextBackendRequest() async throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }
    let source = directory.appendingPathComponent("source", isDirectory: true)
    let candidate = directory.appendingPathComponent("candidate", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
    try Data("candidate".utf8).write(to: candidate.appendingPathComponent("model.json"))
    let executor = FakeTrainingScenarioExecutor(output: try trainingContractRunOutput(passed: true))
    let backend = FakeTrainingBackend(result: TrainingBackendResult(
        finalLoss: 0.2,
        epochs: 1,
        candidateCheckpointID: "ckpt-iter",
        candidateCheckpointURL: candidate
    ))
    let orchestrator = TrainingRunOrchestrator(scenarioExecutor: executor, backend: backend)

    _ = await orchestrator.run(
        config: TrainingRunConfig(
            runID: "run-snapshot-chain",
            mode: .supervised,
            maxIterations: 2,
            minDelta: 0.01,
            enableDatasetExport: true,
            enableTraining: true,
            policyID: "manasMLX"
        ),
        runRequest: try trainingContractRunRequest(),
        trainingTemplate: TrainingBackendRequest(
            datasetURL: directory,
            sequenceLength: 2,
            epochs: 1,
            learningRate: 0.001,
            useAux: false,
            useQualityGating: true,
            maxBatches: 1,
            sourceSnapshot: TrainingBackendSnapshot(
                snapshotID: "source-snapshot",
                checkpointID: "source-checkpoint",
                checkpointURL: source
            )
        ),
        artifactDirectory: directory
    )

    #expect(backend.requests.count == 2)
    #expect(backend.requests.first?.sourceSnapshot?.snapshotID == "source-snapshot")
    #expect(backend.requests.last?.sourceSnapshot?.snapshotID == "run-snapshot-chain-iter-1")
    #expect(backend.requests.last?.sourceSnapshot?.checkpointID == "ckpt-iter")
}

@MainActor
@Test func TrainingRunOrchestratorUsesReinforcementBackendForRolloutMode() async throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }
    let candidate = directory.appendingPathComponent("rl-candidate", isDirectory: true)
    try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
    try Data("candidate".utf8).write(to: candidate.appendingPathComponent("model.json"))
    let executor = FakeTrainingScenarioExecutor(output: try trainingContractRunOutput(passed: true))
    let workerPlan = ParallelTrainingWorkerPlan(
        runID: "run-rl",
        sourceSnapshot: nil,
        workerCount: 4,
        assignments: (0..<4).map { index in
            ParallelTrainingWorkerAssignment(
                workerIndex: index,
                snapshot: WorkerSnapshot(
                    identity: SnapshotIdentity(
                        policyID: "manasMLX",
                        snapshotID: "worker-\(index)"
                    ),
                    workerIndex: index,
                    checkpointURL: directory.appendingPathComponent("snapshots/worker-\(index)")
                ),
                rolloutShardURL: directory.appendingPathComponent("rollouts/worker-\(index)")
            )
        }
    )
    let workerMetrics = workerPlan.assignments.map { assignment in
        ReinforcementTrainingWorkerMetric(
            workerIndex: assignment.workerIndex,
            snapshotID: assignment.snapshot.identity.snapshotID,
            rolloutShardURL: assignment.rolloutShardURL,
            rewardAverage: 0.9 + Double(assignment.workerIndex) * 0.01,
            throughput: 10 + Double(assignment.workerIndex)
        )
    }
    let backend = FakeReinforcementTrainingBackend(result: ReinforcementTrainingBackendResult(
        rewardAverage: 0.9,
        finalLoss: 0.1,
        candidateCheckpointID: "rl-ckpt",
        candidateCheckpointURL: candidate,
        workerMetrics: workerMetrics
    ))
    let orchestrator = TrainingRunOrchestrator(scenarioExecutor: executor, backend: backend)

    let result = await orchestrator.run(
        config: TrainingRunConfig(
            runID: "run-rl",
            mode: .rlRollout,
            maxIterations: 1,
            minDelta: 0.01,
            workerCount: 4,
            enableDatasetExport: true,
            enableTraining: true,
            policyID: "manasMLX",
            parallelWorkerPlan: workerPlan
        ),
        runRequest: try trainingContractRunRequest(),
        trainingTemplate: TrainingBackendRequest(
            datasetURL: directory,
            sequenceLength: 2,
            epochs: 3,
            learningRate: 0.001,
            useAux: false,
            useQualityGating: true,
            maxBatches: 1
        ),
        artifactDirectory: directory
    )

    #expect(backend.supervisedCalls == 0)
    #expect(backend.reinforcementRequests.count == 1)
    #expect(backend.reinforcementRequests.first?.workerCount == 4)
    #expect(backend.reinforcementRequests.first?.workerPlan == workerPlan)
    #expect(backend.reinforcementRequests.first?.algorithm == .actorCritic)
    #expect(result.metrics.contains { $0.kind == .rewardAverage && $0.value == 0.9 })
    #expect(result.metrics.filter { $0.kind == .workerThroughput }.count == 4)
    #expect(result.metrics.contains {
        $0.kind == .workerThroughput
            && $0.workerIndex == 3
            && $0.snapshotID == "worker-3"
            && $0.rolloutShardURL?.lastPathComponent == "worker-3"
            && $0.value == 13
    })
    let artifactBundle = try TrainingRunArtifactValidator().loadAndValidate(from: directory)
    #expect(artifactBundle.metrics.contains {
        $0.kind == .workerThroughput
            && $0.workerIndex == 2
            && $0.snapshotID == "worker-2"
            && $0.rolloutShardURL?.lastPathComponent == "worker-2"
    })
    #expect(result.checkpointDecision.state == .accepted)
}

@MainActor
@Test func TrainingRunOrchestratorRejectsRolloutModeWhenBackendHasNoReinforcementContract() async throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }
    let executor = FakeTrainingScenarioExecutor(output: try trainingContractRunOutput(passed: true))
    let backend = FakeTrainingBackend(result: TrainingBackendResult(finalLoss: 0.1, epochs: 1))
    let orchestrator = TrainingRunOrchestrator(scenarioExecutor: executor, backend: backend)

    let result = await orchestrator.run(
        config: TrainingRunConfig(
            runID: "run-rl-missing-backend",
            mode: .rlRollout,
            maxIterations: 1,
            minDelta: 0.01,
            enableDatasetExport: true,
            enableTraining: true,
            policyID: "manasMLX"
        ),
        runRequest: try trainingContractRunRequest(),
        trainingTemplate: TrainingBackendRequest(
            datasetURL: directory,
            sequenceLength: 2,
            epochs: 1,
            learningRate: 0.001,
            useAux: false,
            useQualityGating: true,
            maxBatches: 1
        ),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .failed)
    #expect(result.convergence.reason.contains("reinforcement-backend-unavailable"))
    #expect(backend.calls == 0)
}

@MainActor
@Test func TrainingProbeOrchestratorWritesComparisonAndReloadsAcceptedCheckpoint() async throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }
    let candidate = directory.appendingPathComponent("probe-candidate", isDirectory: true)
    try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
    try Data("candidate".utf8).write(to: candidate.appendingPathComponent("model.json"))
    let executor = FakeTrainingProbeExecutor()
    let backend = FakeTrainingBackend(result: TrainingBackendResult(
        finalLoss: 0.1,
        epochs: 1,
        candidateCheckpointID: "probe-ckpt",
        candidateCheckpointURL: candidate
    ))
    let probe = TrainingProbeOrchestrator(scenarioExecutor: executor, backend: backend)

    let result = await probe.run(
        probeConfig: TrainingProbeConfig(probeID: "probe-a", minScoreDelta: 0),
        teacherRequest: try trainingContractRunRequest(),
        trainingRequest: try trainingContractRunRequest(),
        trainingConfig: TrainingRunConfig(
            runID: "probe-training-run",
            mode: .supervised,
            maxIterations: 1,
            minDelta: 0.01,
            enableDatasetExport: true,
            enableTraining: true,
            policyID: "manasMLX"
        ),
        trainingTemplate: TrainingBackendRequest(
            datasetURL: directory,
            sequenceLength: 2,
            epochs: 1,
            learningRate: 0.001,
            useAux: false,
            useQualityGating: true,
            maxBatches: 1
        ),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .completed)
    #expect(result.comparison.trainingAccepted)
    #expect(result.comparison.reloadSucceeded)
    #expect(result.comparison.scoreDelta ?? -1 > 0)
    #expect(result.comparison.selectedCheckpointRole == .candidate)
    #expect(result.comparison.selectedCheckpointURL == candidate)
    #expect(result.training.checkpointDecision.state == .staged)
    #expect(result.probeCheckpointDecision.state == .accepted)
    #expect(executor.stages == [.teacherActiveAltitudeHold, .initialPolicy, .trainingIteration, .trainedPolicy])
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("probe-manifest.json").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("comparison.json").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("probe-metrics.jsonl").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("probe-checkpoint-decision.json").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("trained-run.json").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("training/checkpoints/accepted/model.json").path))
    _ = try TrainingRunArtifactValidator().loadAndValidate(
        from: directory.appendingPathComponent("training", isDirectory: true)
    )
    let probeArtifacts = try TrainingProbeArtifactValidator().loadAndValidate(from: directory)
    #expect(probeArtifacts.manifest.probeID == "probe-a")
    #expect(probeArtifacts.training.manifest.runID == "probe-training-run")
    #expect(probeArtifacts.trained?.stage == .trainedPolicy)
    #expect(probeArtifacts.probeMetrics.contains { $0.kind == .teacherDivergenceRegression })
}

@Test func TrainingProbeRunDiagnosticsReportsPerIndexControlStatistics() throws {
    let output = try trainingContractRunOutput(
        passed: true,
        log: try trainingContractMultiDriveSimulationLog()
    )
    let summary = TrainingProbeRunSummary(
        stage: .teacherActiveAltitudeHold,
        output: TrainingScenarioRunOutput(kuyAtt1: output)
    )

    #expect(trainingContractClose(summary.diagnostics.averageDriveActivationByIndex, [0.4, 0.6]))
    #expect(summary.diagnostics.maxDriveActivationByIndex == [0.6, 0.8])
    #expect(summary.diagnostics.averageActuatorValueByIndex == [2.0, 4.0])
    #expect(summary.diagnostics.maxActuatorValueByIndex == [3.0, 5.0])
    #expect(summary.diagnostics.averageMotorFinalOutputByIndex == [4.0, 6.0])
    #expect(summary.diagnostics.maxMotorFinalOutputByIndex == [6.0, 8.0])
}

@MainActor
@Test func TrainingProbeOrchestratorRejectsCheckpointWhenReloadedPolicyRegresses() async throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }
    let candidate = directory.appendingPathComponent("probe-candidate", isDirectory: true)
    try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
    try Data("candidate".utf8).write(to: candidate.appendingPathComponent("model.json"))
    let executor = FakeTrainingProbeExecutor(trainedPasses: false, writesRecoveryDataset: true)
    let backend = FakeTrainingBackend(result: TrainingBackendResult(
        finalLoss: 0.1,
        epochs: 1,
        candidateCheckpointID: "probe-ckpt",
        candidateCheckpointURL: candidate
    ))
    let probe = TrainingProbeOrchestrator(scenarioExecutor: executor, backend: backend)

    let result = await probe.run(
        probeConfig: TrainingProbeConfig(probeID: "probe-regression", minScoreDelta: 0.01),
        teacherRequest: try trainingContractRunRequest(),
        trainingRequest: try trainingContractRunRequest(),
        trainingConfig: TrainingRunConfig(
            runID: "probe-regression-training-run",
            mode: .supervised,
            maxIterations: 1,
            minDelta: 0.01,
            enableDatasetExport: true,
            enableTraining: true,
            policyID: "manasMLX"
        ),
        trainingTemplate: TrainingBackendRequest(
            datasetURL: directory,
            sequenceLength: 2,
            epochs: 1,
            learningRate: 0.001,
            useAux: false,
            useQualityGating: true,
            maxBatches: 1
        ),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .rejected)
    #expect(result.training.checkpointDecision.state == .staged)
    #expect(result.probeCheckpointDecision.state == .rejected)
    #expect(result.comparison.selectedCheckpointRole == .none)
    #expect(result.comparison.selectedCheckpointURL == nil)
    #expect(!result.comparison.meetsMinimumDelta)
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("training/checkpoints/accepted/model.json").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("training/checkpoints/rejected/probe-regression-training-run").path))
    let probeArtifacts = try TrainingProbeArtifactValidator().loadAndValidate(from: directory)
    #expect(probeArtifacts.manifest.terminalState == .rejected)
    #expect(probeArtifacts.probeCheckpointDecision.state == .rejected)
    #expect(probeArtifacts.recoveryRelabelStatus.attempted)
    #expect(probeArtifacts.recoveryRelabelStatus.report?.relabeledEntryCount == 1)

    let recoveryRoot = try #require(probeArtifacts.recoveryRelabelStatus.datasetDirectory)
    let recoveryDataset = try firstTrainingContractDatasetDirectory(in: recoveryRoot)
    let corruptedMetadata = TrainingDatasetMetadata(
        scenarioId: "corrupted-recovery",
        seed: 1,
        timeStep: 0.01,
        determinismTier: "tier0",
        configHash: "corrupted",
        channelCount: 0,
        driveCount: 0,
        recordCount: 1
    )
    try JSONEncoder().encode(corruptedMetadata).write(
        to: recoveryDataset.appendingPathComponent("meta.json"),
        options: [.atomic]
    )

    do {
        _ = try TrainingProbeArtifactValidator().loadAndValidate(from: directory)
        Issue.record("Expected corrupted recovery dataset contract to fail.")
    } catch TrainingProbeArtifactValidator.ValidationError.invalidRecoveryRelabelStatus(let reason) {
        #expect(reason.contains("recovery dataset contract violation"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@MainActor
@Test func TrainingProbeOrchestratorSkipsEmptyRecoveryRelabelDataset() async throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }
    let candidate = directory.appendingPathComponent("probe-candidate", isDirectory: true)
    try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
    try Data("candidate".utf8).write(to: candidate.appendingPathComponent("model.json"))
    let executor = FakeTrainingProbeExecutor(
        trainedPasses: false,
        writesRecoveryDataset: true,
        recoveryRelabeledEntryCount: 0
    )
    let backend = FakeTrainingBackend(result: TrainingBackendResult(
        finalLoss: 0.1,
        epochs: 1,
        candidateCheckpointID: "probe-ckpt",
        candidateCheckpointURL: candidate
    ))
    let probe = TrainingProbeOrchestrator(scenarioExecutor: executor, backend: backend)

    let result = await probe.run(
        probeConfig: TrainingProbeConfig(probeID: "probe-empty-recovery", minScoreDelta: 0.01),
        teacherRequest: try trainingContractRunRequest(),
        trainingRequest: try trainingContractRunRequest(),
        trainingConfig: TrainingRunConfig(
            runID: "probe-empty-recovery-training-run",
            mode: .supervised,
            maxIterations: 1,
            minDelta: 0.01,
            enableDatasetExport: true,
            enableTraining: true,
            policyID: "manasMLX"
        ),
        trainingTemplate: TrainingBackendRequest(
            datasetURL: directory,
            sequenceLength: 2,
            epochs: 1,
            learningRate: 0.001,
            useAux: false,
            useQualityGating: true,
            maxBatches: 1
        ),
        artifactDirectory: directory
    )

    #expect(!result.recoveryRelabelStatus.attempted)
    #expect(result.recoveryRelabelStatus.failureReason == "recovery-relabel-empty")
    let probeArtifacts = try TrainingProbeArtifactValidator().loadAndValidate(from: directory)
    #expect(!probeArtifacts.recoveryRelabelStatus.attempted)
    #expect(probeArtifacts.recoveryRelabelStatus.failureReason == "recovery-relabel-empty")
}

@MainActor
@Test func TrainingProbeOrchestratorSelectsSourceCheckpointWhenCandidateRejected() async throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }
    let source = directory.appendingPathComponent("source-checkpoint", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let candidate = directory.appendingPathComponent("probe-candidate", isDirectory: true)
    try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
    try Data("candidate".utf8).write(to: candidate.appendingPathComponent("model.json"))
    let executor = FakeTrainingProbeExecutor(trainedPasses: false)
    let backend = FakeTrainingBackend(result: TrainingBackendResult(
        finalLoss: 0.1,
        epochs: 1,
        candidateCheckpointID: "probe-ckpt",
        candidateCheckpointURL: candidate
    ))
    let probe = TrainingProbeOrchestrator(scenarioExecutor: executor, backend: backend)

    let result = await probe.run(
        probeConfig: TrainingProbeConfig(probeID: "probe-source-retained", minScoreDelta: 0.01),
        teacherRequest: try trainingContractRunRequest(),
        trainingRequest: try trainingContractRunRequest(),
        trainingConfig: TrainingRunConfig(
            runID: "probe-source-retained-training-run",
            mode: .supervised,
            maxIterations: 1,
            minDelta: 0.01,
            enableDatasetExport: true,
            enableTraining: true,
            parentCheckpointID: "source-checkpoint",
            policyID: "manasMLX"
        ),
        trainingTemplate: TrainingBackendRequest(
            datasetURL: directory,
            sequenceLength: 2,
            epochs: 1,
            learningRate: 0.001,
            useAux: false,
            useQualityGating: true,
            maxBatches: 1,
            sourceSnapshot: TrainingBackendSnapshot(
                snapshotID: "source-snapshot",
                checkpointID: "source-checkpoint",
                checkpointURL: source
            )
        ),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .rejected)
    #expect(result.comparison.selectedCheckpointRole == .source)
    #expect(result.comparison.selectedCheckpointURL == source)
    let probeArtifacts = try TrainingProbeArtifactValidator().loadAndValidate(from: directory)
    #expect(probeArtifacts.comparison.selectedCheckpointRole == .source)
    #expect(probeArtifacts.comparison.selectedCheckpointURL == source)
}

@MainActor
@Test func TrainingProbeArtifactValidatorRejectsReloadedProbeMissingTrainedRun() async throws {
    let directory = try trainingContractTemporaryDirectory()
    defer { trainingContractCleanup(directory) }
    let candidate = directory.appendingPathComponent("probe-candidate", isDirectory: true)
    try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
    try Data("candidate".utf8).write(to: candidate.appendingPathComponent("model.json"))
    let executor = FakeTrainingProbeExecutor()
    let backend = FakeTrainingBackend(result: TrainingBackendResult(
        finalLoss: 0.1,
        epochs: 1,
        candidateCheckpointID: "probe-ckpt",
        candidateCheckpointURL: candidate
    ))
    let probe = TrainingProbeOrchestrator(scenarioExecutor: executor, backend: backend)

    _ = await probe.run(
        probeConfig: TrainingProbeConfig(probeID: "probe-invalid-artifacts", minScoreDelta: 0),
        teacherRequest: try trainingContractRunRequest(),
        trainingRequest: try trainingContractRunRequest(),
        trainingConfig: TrainingRunConfig(
            runID: "probe-invalid-artifacts-training-run",
            mode: .supervised,
            maxIterations: 1,
            minDelta: 0.01,
            enableDatasetExport: true,
            enableTraining: true,
            policyID: "manasMLX"
        ),
        trainingTemplate: TrainingBackendRequest(
            datasetURL: directory,
            sequenceLength: 2,
            epochs: 1,
            learningRate: 0.001,
            useAux: false,
            useQualityGating: true,
            maxBatches: 1
        ),
        artifactDirectory: directory
    )
    try FileManager.default.removeItem(at: directory.appendingPathComponent("trained-run.json"))

    #expect(throws: TrainingProbeArtifactValidator.ValidationError.missingTrainedRunForReloadedProbe) {
        _ = try TrainingProbeArtifactValidator().loadAndValidate(from: directory)
    }
}

@MainActor
@Test func snapshotTrainingBackendContractCarriesRunIdentity() async throws {
    let manifest = LearningRunManifest(
        runID: "run-snapshot",
        mode: .supervised,
        robotManifestID: "robot-a",
        robotManifestHash: nil,
        configHash: "config-a",
        suiteID: "Single Lift",
        seedSet: [1],
        policyID: "manasMLX",
        workerCount: 1,
        startedAt: Date(timeIntervalSince1970: 1),
        terminalState: .running
    )
    let backend = FakeSnapshotTrainingBackend(snapshot: TrainingBackendSnapshot(
        snapshotID: "snapshot-a",
        checkpointID: "checkpoint-a",
        checkpointURL: URL(fileURLWithPath: "/tmp/checkpoint-a"),
        robotManifestID: manifest.robotManifestID,
        configHash: manifest.configHash,
        createdAt: Date(timeIntervalSince1970: 2)
    ))

    let snapshot = try await backend.makeSnapshot(for: manifest)

    #expect(snapshot.snapshotID == "snapshot-a")
    #expect(snapshot.robotManifestID == "robot-a")
    #expect(snapshot.configHash == "config-a")
}

@Test func workerSnapshotLeaseCarriesWorkerLocalIdentity() async throws {
    let provider = FakeSnapshotProvider(lease: SnapshotLease(
        snapshot: WorkerSnapshot(
            identity: SnapshotIdentity(
                policyID: "manasMLX",
                snapshotID: "snapshot-worker-0",
                robotManifestID: "robot-a",
                configHash: "config-a"
            ),
            workerIndex: 0,
            checkpointURL: URL(fileURLWithPath: "/tmp/snapshot-worker-0")
        ),
        leasedAt: Date(timeIntervalSince1970: 1),
        expiresAt: nil
    ))

    let lease = try await provider.leaseSnapshot(workerIndex: 0)

    #expect(lease.snapshot.identity.policyID == "manasMLX")
    #expect(lease.snapshot.identity.snapshotID == "snapshot-worker-0")
    #expect(lease.snapshot.workerIndex == 0)
    #expect(lease.snapshot.checkpointURL.path == "/tmp/snapshot-worker-0")
}

@Test func parallelTrainingWorkerPlanBuildsWorkerLocalAssignments() async throws {
    let rolloutRoot = URL(fileURLWithPath: "/tmp/kuyu-rollout-plan")
    let sourceSnapshot = TrainingBackendSnapshot(
        snapshotID: "source-snapshot",
        checkpointID: "source-checkpoint",
        checkpointURL: URL(fileURLWithPath: "/tmp/source-checkpoint")
    )
    let plan = try await ParallelTrainingWorkerPlanBuilder().build(
        runID: "run-parallel",
        workerCount: 3,
        sourceSnapshot: sourceSnapshot,
        rolloutRoot: rolloutRoot,
        snapshotProvider: WorkerIndexedSnapshotProvider()
    )

    #expect(plan.runID == "run-parallel")
    #expect(plan.workerCount == 3)
    #expect(plan.sourceSnapshot == sourceSnapshot)
    #expect(plan.assignments.map(\.workerIndex) == [0, 1, 2])
    #expect(plan.assignments.map { $0.snapshot.workerIndex } == [0, 1, 2])
    #expect(plan.assignments.last?.rolloutShardURL.path == "/tmp/kuyu-rollout-plan/worker-2")
}

private func metric(
    runID: String = "run",
    iteration: Int,
    kind: TrainingMetricKind,
    value: Double
) -> TrainingMetricRecord {
    TrainingMetricRecord(runID: runID, iteration: iteration, kind: kind, value: value)
}

private func writeTrainingRunArtifact(
    to directory: URL,
    convergenceAccepted: Bool,
    checkpointState: CheckpointDecisionState,
    candidateCheckpointID: String?,
    candidateCheckpointURL: URL?,
    publishedCheckpointURL: URL?,
    outputCheckpointID: String?,
    terminalState: LearningRunTerminalState? = nil,
    completedAt: Date? = Date(timeIntervalSince1970: 2)
) throws {
    let runID = "run-artifact-gate"
    let manifest = LearningRunManifest(
        runID: runID,
        mode: .supervised,
        configHash: "config-hash",
        suiteID: "Lift",
        seedSet: [1],
        policyID: "manasMLX",
        outputCheckpointID: outputCheckpointID,
        workerCount: 1,
        startedAt: Date(timeIntervalSince1970: 1),
        completedAt: completedAt,
        terminalState: terminalState ?? (convergenceAccepted ? .completed : .rejected),
        failureReason: convergenceAccepted ? nil : "not-accepted"
    )
    let convergence = ConvergenceSummary(
        runID: runID,
        accepted: convergenceAccepted,
        reason: convergenceAccepted ? "accepted" : "not-accepted",
        bestCheckpointID: convergenceAccepted ? candidateCheckpointID : nil,
        finalTrainingLoss: 0.2,
        finalValidationLoss: nil,
        rewardMovingAverage: nil,
        passRate: convergenceAccepted ? 1.0 : 0.0,
        failureRate: convergenceAccepted ? 0.0 : 1.0,
        safetyRegressionDetected: false,
        plateauDetected: false,
        overfitRiskDetected: false
    )
    let checkpointDecision = CheckpointDecision(
        runID: runID,
        state: checkpointState,
        reason: checkpointState == .accepted ? "accepted" : "not-accepted",
        candidateCheckpointID: candidateCheckpointID,
        candidateCheckpointURL: candidateCheckpointURL,
        publishedCheckpointURL: publishedCheckpointURL,
        decidedAt: Date(timeIntervalSince1970: 3)
    )
    try TrainingArtifactWriter().write(
        manifest: manifest,
        metrics: [metric(runID: runID, iteration: 1, kind: .score, value: convergenceAccepted ? 1.0 : 0.0)],
        convergence: convergence,
        checkpointDecision: checkpointDecision,
        to: directory
    )
}

@MainActor
private final class FakeTrainingScenarioExecutor: TrainingScenarioExecuting {
    let output: TrainingScenarioRunOutput

    init(output: KuyAtt1RunOutput) {
        self.output = TrainingScenarioRunOutput(kuyAtt1: output)
    }

    func runSuiteForTrainingRun(request: SimulationRunRequest) async throws -> TrainingScenarioRunOutput {
        output
    }
}

@MainActor
private final class FakeTrainingBackend: TrainingBackend {
    let result: TrainingBackendResult
    private(set) var calls = 0
    private(set) var requests: [TrainingBackendRequest] = []

    init(result: TrainingBackendResult) {
        self.result = result
    }

    func trainSupervised(request: TrainingBackendRequest) async throws -> TrainingBackendResult {
        calls += 1
        requests.append(request)
        return result
    }
}

@MainActor
private final class FakeReinforcementTrainingBackend: ReinforcementTrainingBackend {
    let result: ReinforcementTrainingBackendResult
    private(set) var supervisedCalls = 0
    private(set) var reinforcementRequests: [ReinforcementTrainingBackendRequest] = []

    init(result: ReinforcementTrainingBackendResult) {
        self.result = result
    }

    func trainSupervised(request: TrainingBackendRequest) async throws -> TrainingBackendResult {
        supervisedCalls += 1
        return TrainingBackendResult(finalLoss: result.finalLoss ?? 0, epochs: 1)
    }

    func trainReinforcement(request: ReinforcementTrainingBackendRequest) async throws -> ReinforcementTrainingBackendResult {
        reinforcementRequests.append(request)
        return result
    }
}

@MainActor
private final class FailingTrainingBackend: TrainingBackend {
    enum Failure: Error {
        case intentional
    }

    func trainSupervised(request: TrainingBackendRequest) async throws -> TrainingBackendResult {
        throw Failure.intentional
    }
}

@MainActor
private final class FakeSnapshotTrainingBackend: SnapshotTrainingBackend {
    let snapshot: TrainingBackendSnapshot

    init(snapshot: TrainingBackendSnapshot) {
        self.snapshot = snapshot
    }

    func trainSupervised(request: TrainingBackendRequest) async throws -> TrainingBackendResult {
        TrainingBackendResult(finalLoss: 0.1, epochs: 1)
    }

    func makeSnapshot(for manifest: LearningRunManifest) async throws -> TrainingBackendSnapshot {
        snapshot
    }
}

private struct FakeSnapshotProvider: SnapshotProviding {
    let lease: SnapshotLease

    func leaseSnapshot(workerIndex: Int) async throws -> SnapshotLease {
        lease
    }
}

private struct WorkerIndexedSnapshotProvider: SnapshotProviding {
    func leaseSnapshot(workerIndex: Int) async throws -> SnapshotLease {
        SnapshotLease(snapshot: WorkerSnapshot(
            identity: SnapshotIdentity(
                policyID: "manasMLX",
                snapshotID: "snapshot-worker-\(workerIndex)"
            ),
            workerIndex: workerIndex,
            checkpointURL: URL(fileURLWithPath: "/tmp/snapshot-worker-\(workerIndex)")
        ))
    }
}

@MainActor
private final class FakeTrainingProbeExecutor: TrainingProbeScenarioExecuting {
    let trainedPasses: Bool
    let writesRecoveryDataset: Bool
    let recoveryRelabeledEntryCount: Int?
    private(set) var stages: [TrainingProbeStage] = []

    init(
        trainedPasses: Bool = true,
        writesRecoveryDataset: Bool = false,
        recoveryRelabeledEntryCount: Int? = nil
    ) {
        self.trainedPasses = trainedPasses
        self.writesRecoveryDataset = writesRecoveryDataset
        self.recoveryRelabeledEntryCount = recoveryRelabeledEntryCount
    }

    func runProbeSuite(
        stage: TrainingProbeStage,
        request: SimulationRunRequest,
        checkpointURL: URL?
    ) async throws -> TrainingScenarioRunOutput {
        stages.append(stage)
        switch stage {
        case .teacherActiveAltitudeHold:
            return try TrainingScenarioRunOutput(kuyAtt1: trainingContractRunOutput(passed: true))
        case .initialPolicy:
            return try TrainingScenarioRunOutput(kuyAtt1: trainingContractRunOutput(passed: false))
        case .trainingIteration:
            return try TrainingScenarioRunOutput(kuyAtt1: trainingContractRunOutput(passed: true))
        case .trainedPolicy:
            #expect(checkpointURL != nil)
            return try TrainingScenarioRunOutput(kuyAtt1: trainingContractRunOutput(passed: trainedPasses))
        }
    }

    func writeRecoveryRelabelDataset(
        output: TrainingScenarioRunOutput,
        request: SimulationRunRequest,
        to directory: URL,
        includeSuccessfulScenarios: Bool
    ) async throws -> RecoveryRelabelReport? {
        _ = includeSuccessfulScenarios
        guard writesRecoveryDataset else { return nil }
        _ = try TrainingDatasetExporter().write(output: output, to: directory)
        let relabeledEntryCount = recoveryRelabeledEntryCount ?? output.logs.count
        return RecoveryRelabelReport(
            sourceEntryCount: output.logs.count,
            relabeledEntryCount: relabeledEntryCount,
            relabeledStepCount: output.logs.reduce(0) { $0 + $1.log.events.count },
            relabeledCutStepCount: output.logs.reduce(0) { partial, entry in
                partial + entry.log.events.filter { !$0.driveIntents.isEmpty }.count
            },
            skippedEntryCount: 0
        )
    }
}

private func trainingContractRunRequest() throws -> SimulationRunRequest {
    SimulationRunRequest(
        controller: .manasMLX,
        taskMode: .singleLift,
        gains: try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2),
        cutPeriodSteps: 1,
        noise: .zero,
        determinism: try DeterminismConfig(tier: .tier0, tier1Tolerance: nil),
        robotManifestPath: try trainingContractRobotManifestPath(),
        overrideParameters: nil,
        useAux: false,
        useQualityGating: true
    )
}

private func trainingContractRobotManifestPath() throws -> String {
    let manifest = KuyuRobotManifest(
        schemaVersion: "1.0",
        robotID: "quad-test",
        name: "Quad Test",
        category: "quadrotor",
        bodyModel: ModelReference(path: "quad-test.kuyubody.json"),
        embodimentContract: ModelReference(path: "quad-test.embodiment.json")
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(manifest)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-training-contract-quad-test.kuyurobot.json")
    try data.write(to: url, options: .atomic)
    return url.path
}

private func trainingContractRunOutput(passed: Bool) throws -> KuyAtt1RunOutput {
    try trainingContractRunOutput(passed: passed, log: trainingContractSimulationLog())
}

private func trainingContractRunOutput(passed: Bool, log: SimulationLog) throws -> KuyAtt1RunOutput {
    let evaluation = ScenarioEvaluation(
        scenarioId: try ScenarioID("contract-scenario"),
        seed: ScenarioSeed(1),
        passed: passed,
        maxOmega: 0.1,
        maxTiltDegrees: 1.0,
        sustainedViolationSeconds: passed ? 0.0 : 1.0,
        recoveryTimeSeconds: passed ? 0.1 : nil,
        overshootDegrees: passed ? 1.0 : 45.0,
        hfStabilityScore: passed ? 0.9 : 0.1,
        failures: passed ? [] : ["failed"]
    )
    let replay = ReplayVerification.performed([
        ReplayCheckResult(
            scenarioId: evaluation.scenarioId,
            seed: evaluation.seed,
            tier: .tier0,
            passed: true,
            issues: [],
            residuals: .zero
        )
    ])
    let summary = ValidationSummary(
        suitePassed: passed,
        evaluations: [evaluation],
        replay: replay,
        manifest: [],
        aggregate: EvaluationAggregate.from(evaluations: [evaluation])
    )
    return KuyAtt1RunOutput(
        result: SuiteRunResult(
            evaluations: [evaluation],
            replay: replay,
            passed: passed
        ),
        summary: summary,
        logs: [ScenarioLogEntry(
            key: ScenarioKey(scenarioId: log.scenarioId, seed: log.seed),
            log: log
        )]
    )
}

private func trainingContractMultiDriveSimulationLog() throws -> SimulationLog {
    let steps = try [
        trainingContractWorldStep(
            stepIndex: 0,
            driveActivations: [0.2, 0.4],
            actuatorValues: [1.0, 3.0],
            motorFinalOutputs: [2.0, 4.0]
        ),
        trainingContractWorldStep(
            stepIndex: 1,
            driveActivations: [0.6, 0.8],
            actuatorValues: [3.0, 5.0],
            motorFinalOutputs: [6.0, 8.0]
        ),
    ]
    return try SimulationLog(
        scenarioId: try ScenarioID("contract-scenario"),
        seed: ScenarioSeed(1),
        timeStep: TimeStep(delta: 0.01),
        determinism: try DeterminismConfig(tier: .tier0, tier1Tolerance: nil),
        configHash: "contract-config",
        events: steps
    )
}

private func trainingContractSimulationLog() throws -> SimulationLog {
    let step = try trainingContractWorldStep(
        stepIndex: 0,
        driveActivations: [0.5],
        actuatorValues: [],
        motorFinalOutputs: []
    )
    return try SimulationLog(
        scenarioId: try ScenarioID("contract-scenario"),
        seed: ScenarioSeed(1),
        timeStep: TimeStep(delta: 0.01),
        determinism: try DeterminismConfig(tier: .tier0, tier1Tolerance: nil),
        configHash: "contract-config",
        events: [step]
    )
}

private func writeTrainingContractDatasetWithoutTerminalFacts(to directory: URL) throws {
    let record = TrainingDatasetRecord(
        time: 0,
        sensors: [],
        driveIntents: [],
        reflexCorrections: [],
        continueValue: 1.0
    )
    let dataset = TrainingDataset(
        metadata: TrainingDatasetMetadata(
            scenarioId: "invalid-extra",
            seed: 1,
            timeStep: 0.01,
            determinismTier: "tier0",
            configHash: "invalid-extra-config",
            channelCount: 0,
            driveCount: 0,
            recordCount: 1
        ),
        records: [record]
    )
    try TrainingDatasetWriter().write(dataset: dataset, to: directory)
}

private func firstTrainingContractDatasetDirectory(in directory: URL) throws -> URL {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: directory.appendingPathComponent("meta.json").path),
       fileManager.fileExists(atPath: directory.appendingPathComponent("records.jsonl").path) {
        return directory
    }
    let children = try fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )
    let datasets = try children.filter { child in
        let values = try child.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
            && fileManager.fileExists(atPath: child.appendingPathComponent("meta.json").path)
            && fileManager.fileExists(atPath: child.appendingPathComponent("records.jsonl").path)
    }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    return try #require(datasets.first)
}

private func trainingContractWorldStep(
    stepIndex: UInt64,
    driveActivations: [Double],
    actuatorValues: [Double],
    motorFinalOutputs: [Double]
) throws -> WorldStepLog {
    try WorldStepLog(
        time: WorldTime(stepIndex: stepIndex, time: Double(stepIndex) * 0.01),
        events: [.timeAdvance],
        sensorSamples: [
            ChannelSample(channelIndex: 0, value: 0.1, timestamp: Double(stepIndex) * 0.01),
        ],
        driveIntents: driveActivations.enumerated().map { index, activation in
            try DriveIntent(index: DriveIndex(UInt32(index)), activation: activation, parameters: [])
        },
        reflexCorrections: [],
        actuatorValues: actuatorValues.enumerated().map { index, value in
            try ActuatorValue(index: ActuatorIndex(UInt32(index)), value: value)
        },
        actuatorTelemetry: ActuatorTelemetrySnapshot(channels: []),
        motorNerveTrace: MotorNerveTrace(
            uRaw: motorFinalOutputs,
            uSat: motorFinalOutputs,
            uRate: motorFinalOutputs,
            uOut: motorFinalOutputs,
            failsafeActive: false
        ),
        safetyTrace: SafetyTrace(omegaMagnitude: 0.0, tiltRadians: 0.0),
        plantState: PlantStateSnapshot(
            root: RigidBodySnapshot(
                id: "root",
                position: Axis3(x: 0, y: 0, z: 2),
                velocity: Axis3(x: 0, y: 0, z: 0),
                orientation: QuaternionSnapshot(w: 1, x: 0, y: 0, z: 0),
                angularVelocity: Axis3(x: 0, y: 0, z: 0)
            )
        ),
        disturbances: DisturbanceSnapshot(
            forceWorld: Axis3(x: 0, y: 0, z: 0),
            torqueBody: Axis3(x: 0, y: 0, z: 0)
        )
    )
}

private func trainingContractTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-training-contract-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func trainingContractCleanup(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove \(url.path): \(error)")
    }
}

private func trainingContractClose(_ lhs: [Double]?, _ rhs: [Double], tolerance: Double = 1e-9) -> Bool {
    guard let lhs, lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).allSatisfy { abs($0 - $1) <= tolerance }
}
