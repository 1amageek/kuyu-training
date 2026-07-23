import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

@MainActor
public struct TrainingProbeOrchestrator {
    public enum ProbeError: Error, Sendable, Equatable {
        case teacherRunFailed(String)
        case initialRunFailed(String)
        case trainedRunFailed(String)
        case artifactWriteFailed(String)
    }

    public let scenarioExecutor: any TrainingProbeScenarioExecuting
    public let backend: any TrainingBackend
    public let artifactWriter: TrainingProbeArtifactWriter
    public let checkpointRepository: CheckpointRepository

    public init(
        scenarioExecutor: any TrainingProbeScenarioExecuting,
        backend: any TrainingBackend,
        artifactWriter: TrainingProbeArtifactWriter = TrainingProbeArtifactWriter(),
        checkpointRepository: CheckpointRepository = CheckpointRepository()
    ) {
        self.scenarioExecutor = scenarioExecutor
        self.backend = backend
        self.artifactWriter = artifactWriter
        self.checkpointRepository = checkpointRepository
    }

    public func run(
        probeConfig: TrainingProbeConfig,
        teacherRequest: SimulationRunRequest,
        trainingRequest: SimulationRunRequest,
        trainingConfig: TrainingRunConfig,
        trainingTemplate: TrainingBackendRequest,
        artifactDirectory: URL,
        observationMetadata: TrainingObservationMetadata? = nil,
        onEvent: (@Sendable (TrainingProbeEvent) -> Void)? = nil
    ) async -> TrainingProbeResult {
        let startedAt = Date()
        let manifest = TrainingProbeManifest(
            probeID: probeConfig.probeID,
            trainingRunID: trainingConfig.runID,
            startedAt: startedAt,
            terminalState: .running,
            minScoreDelta: probeConfig.minScoreDelta,
            requireAcceptedCheckpoint: probeConfig.requireAcceptedCheckpoint,
            requireTeacherPass: probeConfig.requireTeacherPass,
            requireTrainedPass: probeConfig.requireTrainedPass,
            sourceCheckpointURL: trainingTemplate.sourceSnapshot?.checkpointURL
        )

        let teacher: TrainingProbeRunSummary
        onEvent?(.stageStarted(.teacherActiveAltitudeHold, at: Date()))
        do {
            let output = try await scenarioExecutor.runProbeSuite(
                stage: .teacherActiveAltitudeHold,
                request: teacherRequest,
                checkpointURL: nil
            )
            teacher = TrainingProbeRunSummary(stage: .teacherActiveAltitudeHold, output: output)
            onEvent?(.stageCompleted(teacher, at: Date()))
        } catch {
            onEvent?(.stageFailed(
                .teacherActiveAltitudeHold,
                reason: String(describing: error),
                at: Date()
            ))
            return await failedResult(
                manifest: manifest,
                teacher: nil,
                initial: nil,
                trainingConfig: trainingConfig,
                artifactDirectory: artifactDirectory,
                reason: "teacher-run-failed: \(error)"
            )
        }

        let initial: TrainingProbeRunSummary
        onEvent?(.stageStarted(.initialPolicy, at: Date()))
        do {
            let output = try await scenarioExecutor.runProbeSuite(
                stage: .initialPolicy,
                request: trainingRequest,
                checkpointURL: trainingTemplate.sourceSnapshot?.checkpointURL
            )
            initial = TrainingProbeRunSummary(stage: .initialPolicy, output: output)
            onEvent?(.stageCompleted(initial, at: Date()))
        } catch {
            onEvent?(.stageFailed(
                .initialPolicy,
                reason: String(describing: error),
                at: Date()
            ))
            return await failedResult(
                manifest: manifest,
                teacher: teacher,
                initial: nil,
                trainingConfig: trainingConfig,
                artifactDirectory: artifactDirectory,
                reason: "initial-run-failed: \(error)"
            )
        }

        let trainingDirectory = artifactDirectory.appendingPathComponent("training", isDirectory: true)
        let trainingScenarioAdapter = ProbeTrainingScenarioAdapter(
            executor: scenarioExecutor,
            checkpointURL: trainingTemplate.sourceSnapshot?.checkpointURL
        )
        let training = await TrainingRunOrchestrator(
            scenarioExecutor: trainingScenarioAdapter,
            scenarioEvaluator: trainingScenarioAdapter,
            backend: backend
        ).run(
            config: trainingConfig.withCheckpointPublicationMode(.deferred),
            runRequest: trainingRequest,
            trainingTemplate: trainingTemplate,
            artifactDirectory: trainingDirectory,
            observationMetadata: observationMetadata,
            onEvent: { event in
                onEvent?(.training(event))
            }
        )

        var trained: TrainingProbeRunSummary?
        var trainedOutput: TrainingScenarioRunOutput?
        let evaluationCheckpointURL = training.checkpointDecision.publishedCheckpointURL
            ?? training.checkpointDecision.candidateCheckpointURL
        if training.convergence.accepted || !probeConfig.requireAcceptedCheckpoint {
            onEvent?(.stageStarted(.trainedPolicy, at: Date()))
            // Reuse the last per-iteration evaluation when it is the same checkpoint.
            if let evaluationCheckpointURL,
               let output = trainingScenarioAdapter.cachedEvaluation(
                   for: evaluationCheckpointURL,
                   scope: .acceptance
               ) {
                trainedOutput = output
                trained = TrainingProbeRunSummary(stage: .trainedPolicy, output: output)
                if let trained {
                    onEvent?(.stageCompleted(trained, at: Date()))
                }
            } else {
                do {
                    let output = try await scenarioExecutor.runProbeSuite(
                        stage: .trainedPolicy,
                        request: trainingRequest,
                        checkpointURL: evaluationCheckpointURL
                    )
                    trainedOutput = output
                    trained = TrainingProbeRunSummary(stage: .trainedPolicy, output: output)
                    if let trained {
                        onEvent?(.stageCompleted(trained, at: Date()))
                    }
                } catch {
                    onEvent?(.stageFailed(
                        .trainedPolicy,
                        reason: String(describing: error),
                        at: Date()
                    ))
                    return await failedResult(
                        manifest: manifest,
                        teacher: teacher,
                        initial: initial,
                        training: training,
                        artifactDirectory: artifactDirectory,
                        reason: "trained-run-failed: \(error)"
                    )
                }
            }
        }

        let preliminaryComparison = TrainingProbeComparison(
            probeID: probeConfig.probeID,
            trainingRunID: trainingConfig.runID,
            teacher: teacher,
            initial: initial,
            trained: trained,
            training: training,
            minScoreDelta: probeConfig.minScoreDelta,
            requireTeacherPass: probeConfig.requireTeacherPass,
            requireTrainedPass: probeConfig.requireTrainedPass,
            sourceCheckpointURL: trainingTemplate.sourceSnapshot?.checkpointURL
        )
        let probeCheckpointDecision = finalizeProbeCheckpoint(
            training: training,
            comparison: preliminaryComparison,
            trainingDirectory: trainingDirectory
        )
        let comparison = preliminaryComparison.selectingCheckpoint(from: probeCheckpointDecision)
        let recoveryRelabelStatus = await makeRecoveryRelabelStatus(
            comparison: comparison,
            trainedOutput: trainedOutput,
            trainingRequest: trainingRequest,
            artifactDirectory: artifactDirectory
        )
        return completedResult(
            manifest: manifest,
            teacher: teacher,
            initial: initial,
            training: training,
            trained: trained,
            comparison: comparison,
            probeCheckpointDecision: probeCheckpointDecision,
            recoveryRelabelStatus: recoveryRelabelStatus,
            artifactDirectory: artifactDirectory
        )
    }
}
