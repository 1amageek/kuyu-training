import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import Testing
import KuyuTraining

@Test func generatedArtifactCompatibilityVerifierRoundTripsRunArtifactsThroughFacade() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }

    let result = generatedArtifactRunResult(directory: directory)
    try TrainingArtifactWriter().write(
        manifest: result.manifest,
        metrics: result.metrics,
        convergence: result.convergence,
        checkpointDecision: result.checkpointDecision,
        scenarioRuns: try generatedArtifactScenarioRuns(runID: result.manifest.runID),
        to: directory
    )

    let report = try GeneratedTrainingArtifactCompatibilityVerifier().verify(
        GeneratedTrainingArtifactCompatibilityRequest(runArtifactDirectory: directory)
    )

    #expect(report.runArtifacts?.manifest.runID == result.manifest.runID)
    #expect(report.runArtifacts?.metrics.count == result.metrics.count)
    #expect(report.probeArtifacts == nil)
    #expect(report.checkpointEvaluationArtifact == nil)
}

@Test func generatedArtifactCompatibilityVerifierRoundTripsProbeArtifactsThroughFacade() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }

    let trainingDirectory = directory.appendingPathComponent("training", isDirectory: true)
    let training = generatedArtifactRunResult(directory: trainingDirectory)
    try TrainingArtifactWriter().write(
        manifest: training.manifest,
        metrics: training.metrics,
        convergence: training.convergence,
        checkpointDecision: training.checkpointDecision,
        scenarioRuns: try generatedArtifactScenarioRuns(runID: training.manifest.runID),
        to: trainingDirectory
    )

    let teacher = try generatedArtifactProbeSummary(stage: .teacherActiveAltitudeHold, passed: true)
    let initial = try generatedArtifactProbeSummary(stage: .initialPolicy, passed: false)
    let trained = try generatedArtifactProbeSummary(stage: .trainedPolicy, passed: true)
    let comparison = TrainingProbeComparison(
        probeID: "probe-public-artifact",
        trainingRunID: training.manifest.runID,
        teacher: teacher,
        initial: initial,
        trained: trained,
        training: training,
        minScoreDelta: 0,
        requireTeacherPass: true,
        requireTrainedPass: true
    )
    let probeDecision = CheckpointDecision(
        runID: training.manifest.runID,
        state: .accepted,
        reason: "accepted",
        candidateCheckpointID: "candidate",
        candidateCheckpointURL: directory.appendingPathComponent("candidate"),
        publishedCheckpointURL: directory.appendingPathComponent("published"),
        decidedAt: Date(timeIntervalSince1970: 4)
    )
    let probeResult = TrainingProbeResult(
        manifest: TrainingProbeManifest(
            probeID: "probe-public-artifact",
            trainingRunID: training.manifest.runID,
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 5),
            terminalState: .completed
        ),
        teacher: teacher,
        initial: initial,
        training: training,
        trained: trained,
        comparison: comparison,
        probeCheckpointDecision: probeDecision
    )
    try TrainingProbeArtifactWriter().write(result: probeResult, to: directory)

    let report = try GeneratedTrainingArtifactCompatibilityVerifier().verify(
        GeneratedTrainingArtifactCompatibilityRequest(
            runArtifactDirectory: trainingDirectory,
            probeArtifactDirectory: directory
        )
    )

    #expect(report.runArtifacts?.manifest.runID == training.manifest.runID)
    #expect(report.probeArtifacts?.manifest.probeID == "probe-public-artifact")
    #expect(report.probeArtifacts?.training.manifest.runID == training.manifest.runID)
    #expect(report.probeArtifacts?.trained?.stage == .trainedPolicy)
}

@Test func generatedArtifactCompatibilityVerifierRoundTripsCheckpointEvaluationThroughFacade() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }

    let profile = try TaskEvaluationProfile.profile(task: "attitude")
    let checkpointPath = directory.appendingPathComponent("checkpoint").path
    let artifact = CheckpointEvaluationArtifact(
        evaluationID: "checkpoint-public-artifact",
        startedAt: Date(timeIntervalSince1970: 1),
        task: profile.task,
        profileID: profile.profileID,
        checkpointPath: checkpointPath,
        teacherScore: 1,
        policyScore: 1,
        teacherPassed: true,
        policyPassed: true,
        failureReasons: [],
        expectedQualityKeys: [],
        qualitySummary: [],
        motorMAE: nil,
        driveMAE: nil,
        finalAltitudeDelta: nil,
        policyAverageMotorFinalOutputByIndex: nil,
        teacherAverageMotorFinalOutputByIndex: nil,
        diagnostics: nil
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try encoder.encode(artifact).write(
        to: directory.appendingPathComponent(CheckpointEvaluationArtifact.fileName),
        options: [.atomic]
    )

    let report = try GeneratedTrainingArtifactCompatibilityVerifier().verify(
        GeneratedTrainingArtifactCompatibilityRequest(
            checkpointEvaluation: CheckpointEvaluationArtifactCompatibilityRequest(
                artifactDirectory: directory,
                expectedProfile: profile,
                expectedCheckpointPath: checkpointPath,
                requiresPolicyPass: true
            )
        )
    )

    #expect(report.checkpointEvaluationArtifact?.evaluationID == artifact.evaluationID)
    #expect(report.checkpointEvaluationArtifact?.profileID == profile.profileID)
}

@Test func generatedArtifactCompatibilityVerifierRejectsMissingCheckpointEvaluationArtifact() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }

    let profile = try TaskEvaluationProfile.profile(task: "attitude")

    do {
        _ = try GeneratedTrainingArtifactCompatibilityVerifier().loadCheckpointEvaluationArtifact(
            CheckpointEvaluationArtifactCompatibilityRequest(
                artifactDirectory: directory,
                expectedProfile: profile,
                expectedCheckpointPath: directory.appendingPathComponent("checkpoint").path,
                requiresPolicyPass: true
            )
        )
        Issue.record("Expected missing checkpoint evaluation artifact to fail closed.")
    } catch GeneratedTrainingArtifactCompatibilityVerifier.VerificationError.missingCheckpointEvaluationArtifact(let fileName) {
        #expect(fileName == CheckpointEvaluationArtifact.fileName)
    }
}

@Test func generatedArtifactCompatibilityVerifierValidatesLoadedCheckpointEvaluationArtifact() throws {
    let profile = try TaskEvaluationProfile.profile(task: "attitude")
    let artifact = CheckpointEvaluationArtifact(
        evaluationID: "loaded-checkpoint-public-artifact",
        startedAt: Date(timeIntervalSince1970: 1),
        task: profile.task,
        profileID: profile.profileID,
        checkpointPath: "/tmp/loaded-checkpoint",
        teacherScore: 1,
        policyScore: 1,
        teacherPassed: true,
        policyPassed: true,
        failureReasons: [],
        expectedQualityKeys: [],
        qualitySummary: [],
        motorMAE: nil,
        driveMAE: nil,
        finalAltitudeDelta: nil,
        policyAverageMotorFinalOutputByIndex: nil,
        teacherAverageMotorFinalOutputByIndex: nil,
        diagnostics: nil
    )

    try GeneratedTrainingArtifactCompatibilityVerifier().validateCheckpointEvaluationArtifact(
        artifact,
        expectedProfile: profile,
        expectedCheckpointPath: "/tmp/loaded-checkpoint",
        requiresPolicyPass: true
    )
}

@Test func generatedArtifactCompatibilityVerifierRejectsEmptyRequest() throws {
    do {
        _ = try GeneratedTrainingArtifactCompatibilityVerifier().verify(
            GeneratedTrainingArtifactCompatibilityRequest()
        )
        Issue.record("Expected empty generated artifact verification request to fail closed.")
    } catch GeneratedTrainingArtifactCompatibilityVerifier.VerificationError.emptyRequest {
    }
}

private func generatedArtifactRunResult(directory: URL) -> TrainingRunResult {
    let manifest = LearningRunManifest(
        runID: "run-public-artifact",
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
    let metrics = [
        TrainingMetricRecord(runID: manifest.runID, iteration: 1, kind: .score, value: 1),
        TrainingMetricRecord(runID: manifest.runID, iteration: 1, kind: .loss, value: 0.1),
    ]
    let convergence = ConvergenceSummary(
        runID: manifest.runID,
        accepted: true,
        reason: "accepted",
        bestCheckpointID: "candidate",
        finalTrainingLoss: 0.1,
        finalValidationLoss: nil,
        rewardMovingAverage: nil,
        passRate: 1,
        failureRate: 0,
        safetyRegressionDetected: false,
        plateauDetected: false,
        overfitRiskDetected: false
    )
    let checkpointDecision = CheckpointDecision(
        runID: manifest.runID,
        state: .accepted,
        reason: "accepted",
        candidateCheckpointID: "candidate",
        candidateCheckpointURL: directory.appendingPathComponent("candidate"),
        publishedCheckpointURL: directory.appendingPathComponent("published"),
        decidedAt: Date(timeIntervalSince1970: 3)
    )
    return TrainingRunResult(
        manifest: manifest,
        metrics: metrics,
        convergence: convergence,
        checkpointDecision: checkpointDecision
    )
}

private func generatedArtifactProbeSummary(
    stage: TrainingProbeStage,
    passed: Bool
) throws -> TrainingProbeRunSummary {
    TrainingProbeRunSummary(
        stage: stage,
        output: try TrainingScenarioRunOutput(
            summary: TrainingScenarioRunSummary(
                suitePassed: passed,
                evaluations: [
                    TrainingScenarioEvaluationRecord(
                        scenarioID: "scenario-public-artifact",
                        seed: 1,
                        passed: passed,
                        maxOmega: 0.1,
                        maxTiltDegrees: passed ? 1 : 25,
                        sustainedViolationSeconds: passed ? 0 : 1,
                        recoveryTimeSeconds: passed ? 0.1 : nil,
                        overshootDegrees: passed ? 1 : 30,
                        hfStabilityScore: passed ? 0.9 : 0.1,
                        failures: passed ? [] : ["failed"]
                    )
                ],
                aggregate: TrainingScenarioEvaluationAggregate(
                    averageRecoveryTime: passed ? 0.1 : nil,
                    worstOvershootDegrees: passed ? 1 : 30,
                    averageHfStabilityScore: passed ? 0.9 : 0.1
                ),
                replay: try generatedArtifactReplayVerification(passed: true)
            ),
            logs: [],
            terminalFactsByScenarioKey: [:]
        )
    )
}

private func generatedArtifactScenarioRuns(runID: String) throws -> [TrainingScenarioRunArtifact] {
    [
        TrainingScenarioRunArtifact(
            runID: runID,
            iteration: 1,
            summary: TrainingScenarioRunSummary(
                suitePassed: true,
                evaluations: [
                    try TrainingScenarioEvaluationRecord(
                        scenarioID: "scenario-public-artifact",
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
                replay: try generatedArtifactReplayVerification(passed: true)
            ),
            logCount: 1,
            terminalFactCount: 1
        )
    ]
}

private func generatedArtifactReplayVerification(passed: Bool) throws -> ReplayVerification {
    .performed([
        ReplayCheckResult(
            scenarioId: try ScenarioID("scenario-public-artifact"),
            seed: ScenarioSeed(1),
            tier: .tier0,
            passed: passed,
            issues: passed ? [] : ["failed"],
            residuals: .zero
        )
    ])
}

private func generatedArtifactTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-generated-artifact-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func generatedArtifactCleanup(_ directory: URL) {
    do {
        try FileManager.default.removeItem(at: directory)
    } catch {
        Issue.record("Failed to remove temporary directory: \(error)")
    }
}
