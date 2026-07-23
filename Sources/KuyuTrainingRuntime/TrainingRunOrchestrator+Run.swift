import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

extension TrainingRunOrchestrator {
    /// Runs the training loop.
    ///
    /// `onIterationBoundary` is invoked before each iteration starts — the
    /// only point where external control (pause/stop) may take effect without
    /// tearing an iteration. Returning `.stopRun` ends the run as
    /// `cancelled`; a thrown error ends it as `failed`.
    public func run(
        config: TrainingRunConfig,
        runRequest: SimulationRunRequest,
        trainingTemplate: TrainingBackendRequest,
        artifactDirectory: URL,
        observationMetadata: TrainingObservationMetadata? = nil,
        onIterationBoundary: (@MainActor (Int) async throws -> TrainingIterationBoundaryDirective)? = nil,
        onEvent: (@Sendable (TrainingRunEvent) -> Void)? = nil
    ) async -> TrainingRunResult {
        let startedAt = Date()
        let robotIdentity: RobotManifestIdentity?
        do {
            robotIdentity = try RobotManifestIdentityResolver.resolve(path: runRequest.robotManifestPath)
        } catch {
            return await robotManifestFailureResult(
                config: config,
                runRequest: runRequest,
                artifactDirectory: artifactDirectory,
                startedAt: startedAt,
                error: error,
                onEvent: onEvent
            )
        }
        var manifest = LearningRunManifest(
            runID: config.runID,
            mode: config.mode,
            robotManifestID: robotIdentity?.robotID,
            robotManifestHash: robotIdentity?.sha256,
            configHash: requestHash(runRequest, robotIdentity: robotIdentity),
            suiteID: runRequest.taskMode.rawValue,
            seedSet: [],
            policyID: config.policyID,
            parentCheckpointID: config.parentCheckpointID,
            outputCheckpointID: nil,
            workerCount: config.workerCount,
            startedAt: startedAt,
            terminalState: .running
        )
        onEvent?(.started(manifest))

        var metrics: [TrainingMetricRecord] = []
        var bestScore = -Double.greatestFiniteMagnitude
        var bestCheckpointID: String?
        var bestCheckpointURL: URL?
        var finalCheckpointID: String?
        var finalCheckpointURL: URL?
        var currentSourceSnapshot = trainingTemplate.sourceSnapshot
        var scenarioRuns: [TrainingScenarioRunArtifact] = []
        var sharedScenarioOutput: TrainingScenarioRunOutput?
        var sharedDatasetDirectory: URL?

        var cancelledAtIterationBoundary = false

        for iteration in 1...config.maxIterations {
            if let onIterationBoundary {
                let directive: TrainingIterationBoundaryDirective
                do {
                    directive = try await onIterationBoundary(iteration)
                } catch {
                    return await finish(
                        manifest: manifest,
                        metrics: metrics,
                        bestCheckpointID: bestCheckpointID,
                        bestCheckpointURL: bestCheckpointURL,
                        finalCheckpointID: finalCheckpointID,
                        finalCheckpointURL: finalCheckpointURL,
                        scenarioRuns: scenarioRuns,
                        artifactDirectory: artifactDirectory,
                        state: .failed,
                        failureReason: "iteration-boundary-failed: \(error)",
                        onEvent: onEvent
                    )
                }
                if directive == .stopRun {
                    cancelledAtIterationBoundary = true
                    break
                }
            }
            onEvent?(.iterationStarted(iteration))
            let output: TrainingScenarioRunOutput
            do {
                if config.datasetRefreshPolicy == .shared,
                   let sharedScenarioOutput {
                    output = sharedScenarioOutput
                } else {
                    let generatedOutput = try await scenarioExecutor.runSuiteForTrainingRun(
                        request: runRequest
                    )
                    if config.datasetRefreshPolicy == .shared {
                        sharedScenarioOutput = generatedOutput
                    }
                    output = generatedOutput
                }
            } catch {
                return await finish(
                    manifest: manifest,
                    metrics: metrics,
                    bestCheckpointID: bestCheckpointID,
                    bestCheckpointURL: bestCheckpointURL,
                    finalCheckpointID: finalCheckpointID,
                    finalCheckpointURL: finalCheckpointURL,
                    scenarioRuns: scenarioRuns,
                    artifactDirectory: artifactDirectory,
                    state: .failed,
                    failureReason: "scenario-run-failed: \(error)",
                    onEvent: onEvent
                )
            }
            do {
                try TrainingScenarioReplayValidator().validate(output)
            } catch {
                return await finish(
                    manifest: manifest,
                    metrics: metrics,
                    bestCheckpointID: bestCheckpointID,
                    bestCheckpointURL: bestCheckpointURL,
                    finalCheckpointID: finalCheckpointID,
                    finalCheckpointURL: finalCheckpointURL,
                    scenarioRuns: scenarioRuns,
                    artifactDirectory: artifactDirectory,
                    state: .failed,
                    failureReason: "scenario-replay-validation-failed: \(error)",
                    onEvent: onEvent
                )
            }
            // Persist the run that produced datasets; evaluation output is a separate metric source.
            scenarioRuns.append(TrainingScenarioRunArtifact(
                runID: config.runID,
                iteration: iteration,
                output: output
            ))

            if manifest.seedSet.isEmpty {
                manifest = manifestRecordingScenarioIdentity(manifest, output: output)
            }

            let generatedScore = Self.score(from: output.summary)
            var iterationCheckpointID: String?

            let datasetDirectory: URL
            if config.datasetRefreshPolicy == .shared {
                datasetDirectory = artifactDirectory
                    .appendingPathComponent("datasets", isDirectory: true)
                    .appendingPathComponent("shared", isDirectory: true)
            } else {
                datasetDirectory = artifactDirectory
                    .appendingPathComponent("datasets", isDirectory: true)
                    .appendingPathComponent("iter-\(iteration)", isDirectory: true)
            }

            let shouldExportDataset = config.enableDatasetExport
                && (config.datasetRefreshPolicy == .perIteration || sharedDatasetDirectory == nil)
            if shouldExportDataset {
                do {
                    let exported = try datasetExporter.write(
                        output: output,
                        to: datasetDirectory,
                        observation: observationMetadata
                    )
                    if config.datasetRefreshPolicy == .shared {
                        sharedDatasetDirectory = datasetDirectory
                    }
                    onEvent?(.datasetExported(
                        iteration: iteration,
                        directory: datasetDirectory.path,
                        count: exported.count
                    ))
                } catch {
                    return await finish(
                        manifest: manifest,
                        metrics: metrics,
                        bestCheckpointID: bestCheckpointID,
                        bestCheckpointURL: bestCheckpointURL,
                        finalCheckpointID: finalCheckpointID,
                        finalCheckpointURL: finalCheckpointURL,
                        scenarioRuns: scenarioRuns,
                        artifactDirectory: artifactDirectory,
                        state: .failed,
                        failureReason: "dataset-export-failed: \(error)",
                        onEvent: onEvent
                    )
                }
            }

            if config.enableTraining {
                do {
                    let trainingResult = try await train(
                        mode: config.mode,
                        config: config,
                        manifest: manifest,
                        iteration: iteration,
                        datasetDirectory: datasetDirectory,
                        trainingTemplate: trainingTemplate,
                        sourceSnapshot: currentSourceSnapshot,
                        onEvent: onEvent
                    )
                    finalCheckpointID = trainingResult.candidateCheckpointID
                    finalCheckpointURL = trainingResult.candidateCheckpointURL
                    iterationCheckpointID = trainingResult.candidateCheckpointID
                    if let candidateURL = trainingResult.candidateCheckpointURL {
                        currentSourceSnapshot = TrainingBackendSnapshot(
                            snapshotID: "\(config.runID)-iter-\(iteration)",
                            checkpointID: trainingResult.candidateCheckpointID,
                            checkpointURL: candidateURL,
                            robotManifestID: manifest.robotManifestID,
                            configHash: manifest.configHash
                        )
                    }
                    metrics.append(contentsOf: trainingResult.metrics)
                } catch {
                    return await finish(
                        manifest: manifest,
                        metrics: metrics,
                        bestCheckpointID: bestCheckpointID,
                        bestCheckpointURL: bestCheckpointURL,
                        finalCheckpointID: finalCheckpointID,
                        finalCheckpointURL: finalCheckpointURL,
                        scenarioRuns: scenarioRuns,
                        artifactDirectory: artifactDirectory,
                        state: .failed,
                        failureReason: "backend-failed: \(error)",
                        onEvent: onEvent
                    )
                }
            }

            let evaluatedOutput: TrainingScenarioRunOutput?
            if let scenarioEvaluator,
               let candidateCheckpointURL = finalCheckpointURL,
               iterationCheckpointID != nil {
                do {
                    let output = try await scenarioEvaluator.runSuiteForEvaluation(
                        request: runRequest,
                        checkpointURL: candidateCheckpointURL,
                        scope: config.evaluationScope
                    )
                    try TrainingScenarioReplayValidator().validate(output)
                    evaluatedOutput = output
                } catch {
                    return await finish(
                        manifest: manifest,
                        metrics: metrics,
                        bestCheckpointID: bestCheckpointID,
                        bestCheckpointURL: bestCheckpointURL,
                        finalCheckpointID: finalCheckpointID,
                        finalCheckpointURL: finalCheckpointURL,
                        scenarioRuns: scenarioRuns,
                        artifactDirectory: artifactDirectory,
                        state: .failed,
                        failureReason: "scenario-evaluation-failed: \(error)",
                        onEvent: onEvent
                    )
                }
            } else {
                evaluatedOutput = nil
            }

            let scoredOutput = evaluatedOutput ?? output
            let score = evaluatedOutput.map { Self.score(from: $0.summary) } ?? generatedScore
            metrics.append(contentsOf: suiteMetrics(
                runID: config.runID,
                iteration: iteration,
                output: scoredOutput,
                score: score
            ))
            onEvent?(.suiteCompleted(iteration: iteration, output: scoredOutput, score: score))

            if score > bestScore {
                bestScore = score
                bestCheckpointID = iterationCheckpointID ?? finalCheckpointID ?? bestCheckpointID
                bestCheckpointURL = finalCheckpointURL ?? bestCheckpointURL
            }

            if config.stopOnPass, scoredOutput.summary.suitePassed {
                break
            }
        }

        let convergence = convergenceEvaluator.evaluate(
            runID: config.runID,
            metrics: metrics,
            bestCheckpointID: bestCheckpointID ?? finalCheckpointID
        )
        onEvent?(.convergenceUpdated(convergence))
        let state: LearningRunTerminalState
        let failureReason: String?
        if cancelledAtIterationBoundary {
            state = .cancelled
            failureReason = "cancelled-at-iteration-boundary"
        } else {
            state = convergence.accepted ? .completed : .rejected
            failureReason = convergence.accepted ? nil : convergence.reason
        }
        return await finish(
            manifest: manifest,
            metrics: metrics,
            convergence: convergence,
            finalCheckpointID: finalCheckpointID,
            finalCheckpointURL: finalCheckpointURL,
            scenarioRuns: scenarioRuns,
            artifactDirectory: artifactDirectory,
            checkpointPublicationMode: config.checkpointPublicationMode,
            state: state,
            failureReason: failureReason,
            onEvent: onEvent
        )
    }
}
