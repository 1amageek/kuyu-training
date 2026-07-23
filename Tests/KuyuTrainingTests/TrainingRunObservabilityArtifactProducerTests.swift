import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import Testing
import KuyuTraining

@Test func trainingArtifactWriterPublishesRunObservabilityArtifact() throws {
    let directory = try runObservabilityTemporaryDirectory()
    defer { runObservabilityCleanup(directory) }

    let manifest = runObservabilityManifest()
    let metrics = runObservabilityMetrics(runID: manifest.runID)
    let convergence = runObservabilityConvergence(runID: manifest.runID)
    let checkpointDecision = runObservabilityCheckpointDecision(runID: manifest.runID, directory: directory)
    try TrainingArtifactWriter().write(
        manifest: manifest,
        metrics: metrics,
        convergence: convergence,
        checkpointDecision: checkpointDecision,
        scenarioRuns: [try runObservabilityScenarioRun(runID: manifest.runID)],
        to: directory
    )

    let artifactURL = directory.appendingPathComponent(ConsciousUnconsciousObservabilityArtifact.fileName)
    let artifact = try ConsciousUnconsciousObservabilityArtifactStore().validatedArtifact(at: artifactURL)
    let bundle = try TrainingRunArtifactValidator().validatedBundle(in: directory)

    #expect(bundle.contract.requiredFiles.contains(ConsciousUnconsciousObservabilityArtifact.fileName))
    #expect(bundle.observabilityArtifact == artifact)
    #expect(artifact.runID == manifest.runID)
    #expect(artifact.scenarioID == manifest.suiteID)
    #expect(artifact.descendingSnapshots.first?.source == TrainingRunObservabilityProjection.source)
    #expect(artifact.upwardSummaries.first?.channels.map(\.name) == [
        "salience",
        "risk",
        "uncertainty",
        "constraintPressure",
        "recoveryState",
    ])
    #expect(artifact.arbitrationDecisions.first?.reason == "checkpoint-accepted: accepted")
}

@Test func trainingRunArtifactValidatorRejectsMissingRunObservabilityArtifact() throws {
    let directory = try runObservabilityTemporaryDirectory()
    defer { runObservabilityCleanup(directory) }

    try writeRunObservabilityArtifactBundle(to: directory)
    try FileManager.default.removeItem(
        at: directory.appendingPathComponent(ConsciousUnconsciousObservabilityArtifact.fileName)
    )

    #expect(throws: TrainingRunArtifactValidator.ValidationError.missingFile(
        ConsciousUnconsciousObservabilityArtifact.fileName
    )) {
        _ = try TrainingRunArtifactValidator().validatedBundle(in: directory)
    }
}

@Test func trainingRunArtifactValidatorRejectsStaleRunObservabilityProjection() throws {
    let directory = try runObservabilityTemporaryDirectory()
    defer { runObservabilityCleanup(directory) }

    try writeRunObservabilityArtifactBundle(to: directory)
    let artifactURL = directory.appendingPathComponent(ConsciousUnconsciousObservabilityArtifact.fileName)
    let artifact = try ConsciousUnconsciousObservabilityArtifactStore().validatedArtifact(at: artifactURL)
    let staleSnapshot = try #require(artifact.descendingSnapshots.first).replacingPriority(0)
    let staleArtifact = ConsciousUnconsciousObservabilityArtifact(
        runID: artifact.runID,
        scenarioID: artifact.scenarioID,
        seed: artifact.seed,
        timeStep: artifact.timeStep,
        descendingSnapshots: [staleSnapshot],
        upwardSummaries: artifact.upwardSummaries,
        arbitrationDecisions: artifact.arbitrationDecisions,
        latencyBudgetViolations: artifact.latencyBudgetViolations
    )
    _ = try ConsciousUnconsciousObservabilityArtifactStore().write(staleArtifact, to: artifactURL)

    #expect(throws: TrainingRunArtifactValidator.ValidationError.observabilityProjectionMismatch) {
        _ = try TrainingRunArtifactValidator().validatedBundle(in: directory)
    }
}

private func writeRunObservabilityArtifactBundle(to directory: URL) throws {
    let manifest = runObservabilityManifest()
    try TrainingArtifactWriter().write(
        manifest: manifest,
        metrics: runObservabilityMetrics(runID: manifest.runID),
        convergence: runObservabilityConvergence(runID: manifest.runID),
        checkpointDecision: runObservabilityCheckpointDecision(runID: manifest.runID, directory: directory),
        scenarioRuns: [try runObservabilityScenarioRun(runID: manifest.runID)],
        to: directory
    )
}

private func runObservabilityManifest() -> LearningRunManifest {
    LearningRunManifest(
        runID: "run-observability-producer",
        mode: .rlRollout,
        configHash: "config-hash",
        suiteID: "attitude",
        seedSet: [42],
        policyID: "manasMLX",
        outputCheckpointID: "candidate",
        workerCount: 1,
        startedAt: Date(timeIntervalSince1970: 1),
        completedAt: Date(timeIntervalSince1970: 2),
        terminalState: .completed
    )
}

private func runObservabilityMetrics(runID: String) -> [TrainingMetricRecord] {
    [
        TrainingMetricRecord(
            runID: runID,
            iteration: 1,
            kind: .score,
            value: 0.8,
            timestamp: Date(timeIntervalSince1970: 3)
        ),
        TrainingMetricRecord(
            runID: runID,
            iteration: 1,
            kind: .passRate,
            value: 1,
            timestamp: Date(timeIntervalSince1970: 3)
        ),
        TrainingMetricRecord(
            runID: runID,
            iteration: 1,
            kind: .failureRate,
            value: 0,
            timestamp: Date(timeIntervalSince1970: 3)
        ),
        TrainingMetricRecord(
            runID: runID,
            iteration: 1,
            kind: .safetyViolation,
            value: 0,
            timestamp: Date(timeIntervalSince1970: 3)
        ),
    ]
}

private func runObservabilityConvergence(runID: String) -> ConvergenceSummary {
    ConvergenceSummary(
        runID: runID,
        accepted: true,
        reason: "accepted",
        bestCheckpointID: "candidate",
        finalTrainingLoss: 0.1,
        finalValidationLoss: 0.1,
        rewardMovingAverage: 1,
        passRate: 1,
        failureRate: 0,
        safetyRegressionDetected: false,
        plateauDetected: false,
        overfitRiskDetected: false
    )
}

private func runObservabilityCheckpointDecision(runID: String, directory: URL) -> CheckpointDecision {
    CheckpointDecision(
        runID: runID,
        state: .accepted,
        reason: "accepted",
        candidateCheckpointID: "candidate",
        candidateCheckpointURL: directory.appendingPathComponent("candidate", isDirectory: true),
        publishedCheckpointURL: directory.appendingPathComponent("published", isDirectory: true),
        decidedAt: Date(timeIntervalSince1970: 4)
    )
}

private func runObservabilityScenarioRun(runID: String) throws -> TrainingScenarioRunArtifact {
    TrainingScenarioRunArtifact(
        runID: runID,
        iteration: 1,
        summary: TrainingScenarioRunSummary(
            suitePassed: true,
            evaluations: [
                try TrainingScenarioEvaluationRecord(
                    scenarioID: "attitude",
                    seed: 42,
                    passed: true,
                    maxOmega: 0.1,
                    maxTiltDegrees: 1,
                    sustainedViolationSeconds: 0,
                    recoveryTimeSeconds: 0.1,
                    overshootDegrees: 1,
                    hfStabilityScore: 0.9,
                    failures: []
                )
            ],
            aggregate: TrainingScenarioEvaluationAggregate(
                averageRecoveryTime: 0.1,
                worstOvershootDegrees: 1,
                averageHfStabilityScore: 0.9
            ),
            replay: .performed([
                ReplayCheckResult(
                    scenarioId: try ScenarioID("attitude"),
                    seed: ScenarioSeed(42),
                    tier: .tier0,
                    passed: true,
                    issues: [],
                    residuals: .zero
                )
            ])
        ),
        logCount: 1,
        terminalFactCount: 1
    )
}

private func runObservabilityTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-training-run-observability-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func runObservabilityCleanup(_ directory: URL) {
    do {
        try FileManager.default.removeItem(at: directory)
    } catch {
        Issue.record("Failed to remove temporary directory: \(error)")
    }
}

private extension ConsciousUnconsciousObservabilityArtifact.DescendingSnapshot {
    func replacingPriority(_ priority: Double) -> Self {
        Self(
            stepIndex: stepIndex,
            timestamp: timestamp,
            source: source,
            goalID: goalID,
            priority: priority,
            inhibition: inhibition,
            contextHash: contextHash
        )
    }
}
