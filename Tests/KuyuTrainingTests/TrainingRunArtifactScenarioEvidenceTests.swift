import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import Testing
import KuyuTraining

@Test func trainingRunArtifactValidatorRejectsCompletedRunWithoutScenarioReplayEvidence() throws {
    let directory = try scenarioEvidenceTemporaryDirectory()
    defer { scenarioEvidenceCleanup(directory) }

    try TrainingArtifactWriter().write(
        manifest: scenarioEvidenceManifest(),
        metrics: [scenarioEvidenceMetric(kind: .score)],
        convergence: scenarioEvidenceConvergence(),
        checkpointDecision: scenarioEvidenceCheckpointDecision(directory: directory),
        scenarioRuns: [],
        to: directory
    )

    #expect(throws: TrainingRunArtifactValidator.ValidationError.missingScenarioRunEvidence) {
        _ = try TrainingRunArtifactValidator().loadAndValidate(from: directory)
    }
}

@Test func trainingRunArtifactValidatorRejectsScenarioRunWithoutPerformedReplay() throws {
    let directory = try scenarioEvidenceTemporaryDirectory()
    defer { scenarioEvidenceCleanup(directory) }

    let scenarioRun = TrainingScenarioRunArtifact(
        runID: scenarioEvidenceRunID,
        iteration: 1,
        summary: try scenarioEvidenceSummary(
            replay: .notPerformed(reason: "fixture intentionally omitted replay")
        ),
        logCount: 1,
        terminalFactCount: 1
    )

    try TrainingArtifactWriter().write(
        manifest: scenarioEvidenceManifest(),
        metrics: [scenarioEvidenceMetric(kind: .score)],
        convergence: scenarioEvidenceConvergence(),
        checkpointDecision: scenarioEvidenceCheckpointDecision(directory: directory),
        scenarioRuns: [scenarioRun],
        to: directory
    )

    do {
        _ = try TrainingRunArtifactValidator().loadAndValidate(from: directory)
        Issue.record("Expected scenario replay validation to fail closed.")
    } catch TrainingRunArtifactValidator.ValidationError.scenarioReplayValidationFailed(let iteration, let reason) {
        #expect(iteration == 1)
        #expect(reason.contains("scenario-replay-not-performed"))
    }
}

@Test func trainingRunArtifactValidatorRejectsScenarioMetricWithoutMatchingScenarioRun() throws {
    let directory = try scenarioEvidenceTemporaryDirectory()
    defer { scenarioEvidenceCleanup(directory) }

    let scenarioRun = TrainingScenarioRunArtifact(
        runID: scenarioEvidenceRunID,
        iteration: 2,
        summary: try scenarioEvidenceSummary(replay: scenarioEvidenceReplay()),
        logCount: 1,
        terminalFactCount: 1
    )

    try TrainingArtifactWriter().write(
        manifest: scenarioEvidenceManifest(),
        metrics: [scenarioEvidenceMetric(kind: .score)],
        convergence: scenarioEvidenceConvergence(),
        checkpointDecision: scenarioEvidenceCheckpointDecision(directory: directory),
        scenarioRuns: [scenarioRun],
        to: directory
    )

    #expect(throws: TrainingRunArtifactValidator.ValidationError.invalidScenarioRunIteration(1)) {
        _ = try TrainingRunArtifactValidator().loadAndValidate(from: directory)
    }
}

private let scenarioEvidenceRunID = "run-scenario-evidence"
private let scenarioEvidenceScenarioID = "scenario-evidence"

private func scenarioEvidenceManifest() -> LearningRunManifest {
    LearningRunManifest(
        runID: scenarioEvidenceRunID,
        mode: .supervised,
        configHash: "config-hash",
        suiteID: "attitude",
        seedSet: [1],
        policyID: "policy",
        outputCheckpointID: "candidate",
        workerCount: 1,
        startedAt: Date(timeIntervalSince1970: 1),
        completedAt: Date(timeIntervalSince1970: 2),
        terminalState: .completed
    )
}

private func scenarioEvidenceMetric(kind: TrainingMetricKind) -> TrainingMetricRecord {
    TrainingMetricRecord(
        runID: scenarioEvidenceRunID,
        iteration: 1,
        kind: kind,
        value: 1,
        timestamp: Date(timeIntervalSince1970: 3)
    )
}

private func scenarioEvidenceConvergence() -> ConvergenceSummary {
    ConvergenceSummary(
        runID: scenarioEvidenceRunID,
        accepted: true,
        reason: "accepted",
        bestCheckpointID: "candidate",
        finalTrainingLoss: nil,
        finalValidationLoss: nil,
        rewardMovingAverage: nil,
        passRate: 1,
        failureRate: 0,
        safetyRegressionDetected: false,
        plateauDetected: false,
        overfitRiskDetected: false
    )
}

private func scenarioEvidenceCheckpointDecision(directory: URL) -> CheckpointDecision {
    CheckpointDecision(
        runID: scenarioEvidenceRunID,
        state: .accepted,
        reason: "accepted",
        candidateCheckpointID: "candidate",
        candidateCheckpointURL: directory.appendingPathComponent("candidate"),
        publishedCheckpointURL: directory.appendingPathComponent("published"),
        decidedAt: Date(timeIntervalSince1970: 4)
    )
}

private func scenarioEvidenceSummary(replay: ReplayVerification) throws -> TrainingScenarioRunSummary {
    TrainingScenarioRunSummary(
        suitePassed: true,
        evaluations: [
            try TrainingScenarioEvaluationRecord(
                scenarioID: scenarioEvidenceScenarioID,
                seed: 1,
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
        replay: replay
    )
}

private func scenarioEvidenceReplay() throws -> ReplayVerification {
    .performed([
        ReplayCheckResult(
            scenarioId: try ScenarioID(scenarioEvidenceScenarioID),
            seed: ScenarioSeed(1),
            tier: .tier0,
            passed: true,
            issues: [],
            residuals: .zero
        )
    ])
}

private func scenarioEvidenceTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-training-scenario-evidence-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func scenarioEvidenceCleanup(_ directory: URL) {
    do {
        try FileManager.default.removeItem(at: directory)
    } catch {
        Issue.record("Failed to remove temporary directory: \(error)")
    }
}
