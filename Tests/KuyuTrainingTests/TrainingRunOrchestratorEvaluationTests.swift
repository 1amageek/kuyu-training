import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import Testing
@testable import KuyuTraining
@testable import KuyuTrainingRuntime

@Suite(.serialized)
@MainActor
struct TrainingRunOrchestratorEvaluationTests {
    @Test func checkpointPublicationModeCopyPreservesConfiguration() {
        let config = TrainingRunConfig(
            runID: "configuration-copy",
            mode: .imaginationRL,
            maxIterations: 7,
            minDelta: 0.125,
            workerCount: 3,
            enableDatasetExport: false,
            enableTraining: false,
            stopOnPass: true,
            parentCheckpointID: "parent",
            policyID: "policy",
            parallelWorkerPlan: nil,
            checkpointPublicationMode: .immediate,
            datasetRefreshPolicy: .shared,
            evaluationScope: .progress
        )
        var expected = config
        expected.checkpointPublicationMode = TrainingRunConfig.CheckpointPublicationMode.deferred

        #expect(config.withCheckpointPublicationMode(.deferred) == expected)
    }

    @Test func evaluationScoreDoesNotReplaceDatasetGenerationEvidence() async throws {
        let artifactDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("training-evaluation-contract-\(UUID().uuidString)", isDirectory: true)
        defer {
            do {
                try FileManager.default.removeItem(at: artifactDirectory)
            } catch {
                Issue.record("Failed to remove test artifacts: \(error)")
            }
        }

        let candidateCheckpoint = artifactDirectory.appendingPathComponent("candidate", isDirectory: true)
        try FileManager.default.createDirectory(at: candidateCheckpoint, withIntermediateDirectories: true)
        try Data("candidate".utf8).write(
            to: candidateCheckpoint.appendingPathComponent("model.json"),
            options: [.atomic]
        )

        let generatedOutput = try makeOutput(passed: false)
        let evaluatedOutput = try makeOutput(passed: true)
        let executor = EvaluationScenarioExecutor(
            generatedOutput: generatedOutput,
            evaluatedOutput: evaluatedOutput
        )
        let backend = EvaluationBackend(candidateCheckpoint: candidateCheckpoint)
        let orchestrator = TrainingRunOrchestrator(
            scenarioExecutor: executor,
            scenarioEvaluator: executor,
            backend: backend
        )

        let result = await orchestrator.run(
            config: TrainingRunConfig(
                runID: "evaluation-contract",
                mode: .supervised,
                maxIterations: 2,
                minDelta: 0,
                enableDatasetExport: false,
                enableTraining: true,
                policyID: "test-policy"
            ),
            runRequest: try makeRequest(),
            trainingTemplate: TrainingBackendRequest(
                datasetURL: artifactDirectory,
                sequenceLength: 2,
                epochs: 1,
                learningRate: 0.001,
                useAux: false,
                useQualityGating: false,
                maxBatches: 1
            ),
            artifactDirectory: artifactDirectory
        )

        let scoreMetrics = result.metrics.filter { $0.kind == .score }
        let scenarioCountMetrics = result.metrics.filter { $0.kind == .evaluationScenarioCount }
        let artifactBundle = try TrainingRunArtifactValidator().validatedBundle(in: artifactDirectory)
        #expect(executor.evaluationCalls == 2)
        #expect(scoreMetrics.map(\.iteration) == [1, 2])
        #expect(scoreMetrics.allSatisfy { $0.value == 1 })
        #expect(scenarioCountMetrics.map(\.value) == [1, 1])
        #expect(artifactBundle.scenarioRuns.count == 2)
        #expect(artifactBundle.scenarioRuns.allSatisfy { !$0.summary.suitePassed })
        #expect(artifactBundle.scenarioRuns.allSatisfy { $0.logCount == generatedOutput.logs.count })
    }

    @Test func sharedDatasetPolicyReusesTrainingScenarioOutput() async throws {
        let artifactDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("training-shared-dataset-policy-\(UUID().uuidString)", isDirectory: true)
        defer {
            do {
                try FileManager.default.removeItem(at: artifactDirectory)
            } catch {
                Issue.record("Failed to remove test artifacts: \(error)")
            }
        }

        let output = try makeOutput(passed: true)
        let executor = EvaluationScenarioExecutor(
            generatedOutput: output,
            evaluatedOutput: output
        )
        let orchestrator = TrainingRunOrchestrator(
            scenarioExecutor: executor,
            backend: EvaluationBackend(
                candidateCheckpoint: artifactDirectory.appendingPathComponent("candidate", isDirectory: true)
            )
        )

        _ = await orchestrator.run(
            config: TrainingRunConfig(
                runID: "shared-dataset-policy",
                mode: .supervised,
                maxIterations: 3,
                minDelta: 0,
                enableDatasetExport: false,
                enableTraining: false,
                policyID: "test-policy",
                datasetRefreshPolicy: .shared
            ),
            runRequest: try makeRequest(),
            trainingTemplate: TrainingBackendRequest(
                datasetURL: artifactDirectory,
                sequenceLength: 2,
                epochs: 1,
                learningRate: 0.001,
                useAux: false,
                useQualityGating: false,
                maxBatches: 1
            ),
            artifactDirectory: artifactDirectory
        )

        #expect(executor.trainingCalls == 1)
    }

    private func makeOutput(passed: Bool) throws -> TrainingScenarioRunOutput {
        let scenarioID = try ScenarioID("evaluation-contract")
        let seed = ScenarioSeed(1)
        let evaluation = TrainingScenarioEvaluationRecord(
            scenarioID: scenarioID,
            seed: seed,
            passed: passed,
            maxOmega: 0,
            maxTiltDegrees: 0,
            sustainedViolationSeconds: 0,
            recoveryTimeSeconds: nil,
            overshootDegrees: nil,
            hfStabilityScore: nil,
            failures: []
        )
        let replay = ReplayCheckResult(
            scenarioId: scenarioID,
            seed: seed,
            tier: .tier0,
            passed: true,
            issues: [],
            residuals: .zero
        )
        return TrainingScenarioRunOutput(
            summary: TrainingScenarioRunSummary(
                suitePassed: passed,
                evaluations: [evaluation],
                aggregate: TrainingScenarioEvaluationAggregate(
                    averageRecoveryTime: nil,
                    worstOvershootDegrees: nil,
                    averageHfStabilityScore: nil
                ),
                replay: .performed([replay])
            ),
            logs: [],
            terminalFactsByScenarioKey: [:]
        )
    }

    private func makeRequest() throws -> SimulationRunRequest {
        SimulationRunRequest(
            controller: .manasMLX,
            taskMode: .singleLift,
            gains: try ImuRateDampingCutGains(kp: 2, kd: 0.25, yawDamping: 0.2),
            cutPeriodSteps: 1,
            noise: .zero,
            determinism: try DeterminismConfig(tier: .tier0, tier1Tolerance: nil),
            robotManifestPath: "",
            overrideParameters: nil,
            useAux: false,
            useQualityGating: false
        )
    }
}

@MainActor
private final class EvaluationScenarioExecutor: TrainingScenarioExecuting, TrainingScenarioEvaluating {
    let generatedOutput: TrainingScenarioRunOutput
    let evaluatedOutput: TrainingScenarioRunOutput
    private(set) var evaluationCalls = 0
    private(set) var trainingCalls = 0

    init(
        generatedOutput: TrainingScenarioRunOutput,
        evaluatedOutput: TrainingScenarioRunOutput
    ) {
        self.generatedOutput = generatedOutput
        self.evaluatedOutput = evaluatedOutput
    }

    func runSuiteForTrainingRun(request: SimulationRunRequest) async throws -> TrainingScenarioRunOutput {
        trainingCalls += 1
        return generatedOutput
    }

    func runSuiteForEvaluation(
        request: SimulationRunRequest,
        checkpointURL: URL,
        scope: TrainingRunConfig.EvaluationScope
    ) async throws -> TrainingScenarioRunOutput {
        #expect(scope == .acceptance)
        evaluationCalls += 1
        return evaluatedOutput
    }
}

@MainActor
private final class EvaluationBackend: TrainingBackend {
    let candidateCheckpoint: URL

    init(candidateCheckpoint: URL) {
        self.candidateCheckpoint = candidateCheckpoint
    }

    func trainSupervised(request: TrainingBackendRequest) async throws -> TrainingBackendResult {
        TrainingBackendResult(
            finalLoss: 0.2,
            epochs: 1,
            candidateCheckpointID: "evaluation-candidate",
            candidateCheckpointURL: candidateCheckpoint
        )
    }
}
