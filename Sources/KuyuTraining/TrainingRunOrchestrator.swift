import Foundation
import KuyuCore
import KuyuScenarios

public struct TrainingBackendRequest: Sendable, Equatable {
    public let datasetURL: URL
    public let additionalDatasetURLs: [URL]
    public let additionalDatasetRepeatCount: Int
    public let sequenceLength: Int
    public let epochs: Int
    public let learningRate: Double
    public let useAux: Bool
    public let useQualityGating: Bool
    public let maxBatches: Int?
    public let sourceSnapshot: TrainingBackendSnapshot?

    public init(
        datasetURL: URL,
        additionalDatasetURLs: [URL] = [],
        additionalDatasetRepeatCount: Int = 1,
        sequenceLength: Int,
        epochs: Int,
        learningRate: Double,
        useAux: Bool,
        useQualityGating: Bool,
        maxBatches: Int? = nil,
        sourceSnapshot: TrainingBackendSnapshot? = nil
    ) {
        self.datasetURL = datasetURL
        self.additionalDatasetURLs = additionalDatasetURLs
        self.additionalDatasetRepeatCount = max(1, additionalDatasetRepeatCount)
        self.sequenceLength = sequenceLength
        self.epochs = epochs
        self.learningRate = learningRate
        self.useAux = useAux
        self.useQualityGating = useQualityGating
        self.maxBatches = maxBatches
        self.sourceSnapshot = sourceSnapshot
    }
}

public struct TrainingBackendResult: Sendable, Equatable {
    public let finalLoss: Double
    public let epochs: Int
    public let candidateCheckpointID: String?
    public let candidateCheckpointURL: URL?

    public init(
        finalLoss: Double,
        epochs: Int,
        candidateCheckpointID: String? = nil,
        candidateCheckpointURL: URL? = nil
    ) {
        self.finalLoss = finalLoss
        self.epochs = epochs
        self.candidateCheckpointID = candidateCheckpointID
        self.candidateCheckpointURL = candidateCheckpointURL
    }
}

@MainActor
public protocol TrainingScenarioExecuting {
    func runSuiteForTrainingRun(request: SimulationRunRequest) async throws -> KuyAtt1RunOutput
}

@MainActor
public protocol TrainingBackend {
    func trainSupervised(request: TrainingBackendRequest) async throws -> TrainingBackendResult
}

public struct TrainingRunConfig: Sendable, Equatable {
    public enum CheckpointPublicationMode: String, Sendable, Codable, Equatable {
        case immediate
        case deferred
    }

    public let runID: String
    public let mode: LearningRunMode
    public let maxIterations: Int
    public let minDelta: Double
    public let workerCount: Int
    public let enableDatasetExport: Bool
    public let enableTraining: Bool
    public let stopOnPass: Bool
    public let parentCheckpointID: String?
    public let policyID: String
    public let parallelWorkerPlan: ParallelTrainingWorkerPlan?
    public let checkpointPublicationMode: CheckpointPublicationMode

    public init(
        runID: String = UUID().uuidString,
        mode: LearningRunMode = .supervised,
        maxIterations: Int,
        minDelta: Double,
        workerCount: Int = 1,
        enableDatasetExport: Bool = true,
        enableTraining: Bool = true,
        stopOnPass: Bool = false,
        parentCheckpointID: String? = nil,
        policyID: String,
        parallelWorkerPlan: ParallelTrainingWorkerPlan? = nil,
        checkpointPublicationMode: CheckpointPublicationMode = .immediate
    ) {
        self.runID = runID
        self.mode = mode
        self.maxIterations = max(1, maxIterations)
        self.minDelta = minDelta
        self.workerCount = max(1, workerCount)
        self.enableDatasetExport = enableDatasetExport
        self.enableTraining = enableTraining
        self.stopOnPass = stopOnPass
        self.parentCheckpointID = parentCheckpointID
        self.policyID = policyID
        self.parallelWorkerPlan = parallelWorkerPlan
        self.checkpointPublicationMode = checkpointPublicationMode
    }
}

public enum TrainingRunEvent: Sendable, Equatable {
    case started(LearningRunManifest)
    case iterationStarted(Int)
    case suiteCompleted(iteration: Int, output: KuyAtt1RunOutput, score: Double)
    case datasetExported(iteration: Int, directory: String, count: Int)
    case trainingCompleted(iteration: Int, result: TrainingBackendResult)
    case reinforcementTrainingCompleted(iteration: Int, result: ReinforcementTrainingBackendResult)
    case convergenceUpdated(ConvergenceSummary)
    case completed(TrainingRunResult)
}

public struct TrainingRunResult: Sendable, Equatable {
    public let manifest: LearningRunManifest
    public let metrics: [TrainingMetricRecord]
    public let convergence: ConvergenceSummary
    public let checkpointDecision: CheckpointDecision

    public init(
        manifest: LearningRunManifest,
        metrics: [TrainingMetricRecord],
        convergence: ConvergenceSummary,
        checkpointDecision: CheckpointDecision
    ) {
        self.manifest = manifest
        self.metrics = metrics
        self.convergence = convergence
        self.checkpointDecision = checkpointDecision
    }
}

@MainActor
public struct TrainingRunOrchestrator {
    public enum RunError: Error, Equatable {
        case datasetExportFailed(String)
        case backendFailed(String)
        case artifactWriteFailed(String)
    }

    public let scenarioExecutor: any TrainingScenarioExecuting
    public let backend: any TrainingBackend
    public let datasetExporter: TrainingDatasetExporter
    public let artifactWriter: any MetricsWriting
    public let convergenceEvaluator: ConvergenceEvaluator
    public let checkpointPolicy: CheckpointAcceptancePolicy
    public let checkpointRepository: CheckpointRepository

    public init(
        scenarioExecutor: any TrainingScenarioExecuting,
        backend: any TrainingBackend,
        datasetExporter: TrainingDatasetExporter = TrainingDatasetExporter(),
        artifactWriter: any MetricsWriting = TrainingArtifactWriter(),
        convergenceEvaluator: ConvergenceEvaluator = ConvergenceEvaluator(),
        checkpointPolicy: CheckpointAcceptancePolicy = CheckpointAcceptancePolicy(),
        checkpointRepository: CheckpointRepository = CheckpointRepository()
    ) {
        self.scenarioExecutor = scenarioExecutor
        self.backend = backend
        self.datasetExporter = datasetExporter
        self.artifactWriter = artifactWriter
        self.convergenceEvaluator = convergenceEvaluator
        self.checkpointPolicy = checkpointPolicy
        self.checkpointRepository = checkpointRepository
    }

    public func run(
        config: TrainingRunConfig,
        runRequest: SimulationRunRequest,
        trainingTemplate: TrainingBackendRequest,
        artifactDirectory: URL,
        observationMetadata: TrainingObservationMetadata? = nil,
        onEvent: (@Sendable (TrainingRunEvent) -> Void)? = nil
    ) async -> TrainingRunResult {
        let startedAt = Date()
        var manifest = LearningRunManifest(
            runID: config.runID,
            mode: config.mode,
            descriptorID: descriptorID(from: runRequest),
            descriptorHash: descriptorHash(from: runRequest),
            configHash: requestHash(runRequest),
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

        for iteration in 1...config.maxIterations {
            onEvent?(.iterationStarted(iteration))
            let output: KuyAtt1RunOutput
            do {
                output = try await scenarioExecutor.runSuiteForTrainingRun(request: runRequest)
            } catch {
                return await finish(
                    manifest: manifest,
                    metrics: metrics,
                    bestCheckpointID: bestCheckpointID,
                    bestCheckpointURL: bestCheckpointURL,
                    finalCheckpointID: finalCheckpointID,
                    finalCheckpointURL: finalCheckpointURL,
                    artifactDirectory: artifactDirectory,
                    state: .failed,
                    failureReason: "scenario-run-failed: \(error)",
                    onEvent: onEvent
                )
            }

            if manifest.seedSet.isEmpty {
                manifest = LearningRunManifest(
                    runID: manifest.runID,
                    mode: manifest.mode,
                    descriptorID: manifest.descriptorID,
                    descriptorHash: manifest.descriptorHash,
                    configHash: output.logs.first?.log.configHash ?? manifest.configHash,
                    suiteID: manifest.suiteID,
                    seedSet: output.logs.map { $0.key.seed.rawValue },
                    policyID: manifest.policyID,
                    parentCheckpointID: manifest.parentCheckpointID,
                    outputCheckpointID: nil,
                    workerCount: manifest.workerCount,
                    startedAt: manifest.startedAt,
                    terminalState: .running
                )
            }

            let score = Self.score(from: output.summary)
            metrics.append(contentsOf: suiteMetrics(runID: config.runID, iteration: iteration, output: output, score: score))
            onEvent?(.suiteCompleted(iteration: iteration, output: output, score: score))
            var iterationCheckpointID: String?

            let iterationDatasetDirectory = artifactDirectory
                .appendingPathComponent("datasets", isDirectory: true)
                .appendingPathComponent("iter-\(iteration)", isDirectory: true)

            if config.enableDatasetExport {
                do {
                    let exported = try datasetExporter.write(
                        output: output,
                        to: iterationDatasetDirectory,
                        observation: observationMetadata
                    )
                    onEvent?(.datasetExported(
                        iteration: iteration,
                        directory: iterationDatasetDirectory.path,
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
                        datasetDirectory: iterationDatasetDirectory,
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
                            descriptorID: manifest.descriptorID,
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
                        artifactDirectory: artifactDirectory,
                        state: .failed,
                        failureReason: "backend-failed: \(error)",
                        onEvent: onEvent
                    )
                }
            }

            if score > bestScore {
                bestScore = score
                bestCheckpointID = iterationCheckpointID ?? finalCheckpointID ?? bestCheckpointID
                bestCheckpointURL = finalCheckpointURL ?? bestCheckpointURL
            }

            if config.stopOnPass, output.summary.suitePassed {
                break
            }
        }

        let convergence = convergenceEvaluator.evaluate(
            runID: config.runID,
            metrics: metrics,
            bestCheckpointID: bestCheckpointID ?? finalCheckpointID
        )
        onEvent?(.convergenceUpdated(convergence))
        let state: LearningRunTerminalState = convergence.accepted ? .completed : .rejected
        return await finish(
            manifest: manifest,
            metrics: metrics,
            convergence: convergence,
            finalCheckpointID: finalCheckpointID,
            finalCheckpointURL: finalCheckpointURL,
            artifactDirectory: artifactDirectory,
            checkpointPublicationMode: config.checkpointPublicationMode,
            state: state,
            failureReason: convergence.accepted ? nil : convergence.reason,
            onEvent: onEvent
        )
    }

    private struct IterationTrainingResult: Sendable, Equatable {
        let metrics: [TrainingMetricRecord]
        let candidateCheckpointID: String?
        let candidateCheckpointURL: URL?
    }

    private func train(
        mode: LearningRunMode,
        config: TrainingRunConfig,
        manifest: LearningRunManifest,
        iteration: Int,
        datasetDirectory: URL,
        trainingTemplate: TrainingBackendRequest,
        sourceSnapshot: TrainingBackendSnapshot?,
        onEvent: (@Sendable (TrainingRunEvent) -> Void)?
    ) async throws -> IterationTrainingResult {
        switch mode {
        case .supervised:
            let supervisedDatasetDirectory = try supervisedDatasetDirectory(
                exportedDatasetDirectory: datasetDirectory,
                additionalDatasetURLs: trainingTemplate.additionalDatasetURLs,
                additionalDatasetRepeatCount: trainingTemplate.additionalDatasetRepeatCount,
                iteration: iteration
            )
            let request = TrainingBackendRequest(
                datasetURL: supervisedDatasetDirectory,
                additionalDatasetURLs: [],
                additionalDatasetRepeatCount: 1,
                sequenceLength: trainingTemplate.sequenceLength,
                epochs: trainingTemplate.epochs,
                learningRate: trainingTemplate.learningRate,
                useAux: trainingTemplate.useAux,
                useQualityGating: trainingTemplate.useQualityGating,
                maxBatches: trainingTemplate.maxBatches,
                sourceSnapshot: sourceSnapshot
            )
            let result = try await backend.trainSupervised(request: request)
            onEvent?(.trainingCompleted(iteration: iteration, result: result))
            return IterationTrainingResult(
                metrics: [
                    TrainingMetricRecord(
                        runID: config.runID,
                        iteration: iteration,
                        kind: .loss,
                        value: result.finalLoss
                    )
                ],
                candidateCheckpointID: result.candidateCheckpointID,
                candidateCheckpointURL: result.candidateCheckpointURL
            )
        case .rlRollout, .imaginationRL:
            guard let reinforcementBackend = backend as? any ReinforcementTrainingBackend else {
                throw RunError.backendFailed("reinforcement-backend-unavailable")
            }
            let request = ReinforcementTrainingBackendRequest(
                rolloutDatasetURL: datasetDirectory,
                sourceSnapshot: sourceSnapshot,
                workerCount: config.workerCount,
                iterations: trainingTemplate.epochs,
                learningRate: trainingTemplate.learningRate,
                algorithm: mode == .imaginationRL ? .imagination : .actorCritic,
                maxBatches: trainingTemplate.maxBatches,
                workerPlan: config.parallelWorkerPlan
            )
            let result = try await reinforcementBackend.trainReinforcement(request: request)
            onEvent?(.reinforcementTrainingCompleted(iteration: iteration, result: result))
            var metrics = [
                TrainingMetricRecord(
                    runID: config.runID,
                    iteration: iteration,
                    kind: .rewardAverage,
                    value: result.rewardAverage
                )
            ]
            if let finalLoss = result.finalLoss {
                metrics.append(TrainingMetricRecord(
                    runID: config.runID,
                    iteration: iteration,
                    kind: .loss,
                    value: finalLoss
                ))
            }
            metrics.append(contentsOf: workerMetricRecords(
                runID: config.runID,
                iteration: iteration,
                workerMetrics: result.workerMetrics
            ))
            return IterationTrainingResult(
                metrics: metrics,
                candidateCheckpointID: result.candidateCheckpointID,
                candidateCheckpointURL: result.candidateCheckpointURL
            )
        }
    }

    private func workerMetricRecords(
        runID: String,
        iteration: Int,
        workerMetrics: [ReinforcementTrainingWorkerMetric]
    ) -> [TrainingMetricRecord] {
        workerMetrics.flatMap { metric in
            [
                TrainingMetricRecord(
                    runID: runID,
                    iteration: iteration,
                    kind: .rewardAverage,
                    value: metric.rewardAverage,
                    workerIndex: metric.workerIndex,
                    snapshotID: metric.snapshotID,
                    rolloutShardURL: metric.rolloutShardURL
                ),
                TrainingMetricRecord(
                    runID: runID,
                    iteration: iteration,
                    kind: .workerThroughput,
                    value: metric.throughput,
                    workerIndex: metric.workerIndex,
                    snapshotID: metric.snapshotID,
                    rolloutShardURL: metric.rolloutShardURL
                )
            ]
        }
    }

    private func supervisedDatasetDirectory(
        exportedDatasetDirectory: URL,
        additionalDatasetURLs: [URL],
        additionalDatasetRepeatCount: Int,
        iteration: Int
    ) throws -> URL {
        guard !additionalDatasetURLs.isEmpty else {
            return exportedDatasetDirectory
        }
        let repeatedAdditionalDatasetURLs = additionalDatasetURLs.flatMap { url in
            Array(repeating: url, count: max(1, additionalDatasetRepeatCount))
        }
        let mixedDirectory = exportedDatasetDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("iter-\(iteration)-mixed", isDirectory: true)
        _ = try TrainingDatasetMixer().mix(
            sources: repeatedAdditionalDatasetURLs + [exportedDatasetDirectory],
            to: mixedDirectory
        )
        return mixedDirectory
    }

    private func finish(
        manifest: LearningRunManifest,
        metrics: [TrainingMetricRecord],
        bestCheckpointID: String?,
        bestCheckpointURL: URL?,
        finalCheckpointID: String?,
        finalCheckpointURL: URL?,
        artifactDirectory: URL,
        state: LearningRunTerminalState,
        failureReason: String?,
        onEvent: (@Sendable (TrainingRunEvent) -> Void)?
    ) async -> TrainingRunResult {
        let convergence = convergenceEvaluator.evaluate(
            runID: manifest.runID,
            metrics: metrics,
            bestCheckpointID: bestCheckpointID ?? finalCheckpointID
        )
        return await finish(
            manifest: manifest,
            metrics: metrics,
            convergence: ConvergenceSummary(
                runID: convergence.runID,
                accepted: false,
                reason: failureReason ?? convergence.reason,
                bestCheckpointID: convergence.bestCheckpointID,
                finalTrainingLoss: convergence.finalTrainingLoss,
                finalValidationLoss: convergence.finalValidationLoss,
                rewardMovingAverage: convergence.rewardMovingAverage,
                passRate: convergence.passRate,
                failureRate: convergence.failureRate,
                safetyRegressionDetected: convergence.safetyRegressionDetected,
                plateauDetected: convergence.plateauDetected,
                overfitRiskDetected: convergence.overfitRiskDetected
            ),
            finalCheckpointID: finalCheckpointID,
            finalCheckpointURL: finalCheckpointURL,
            artifactDirectory: artifactDirectory,
            checkpointPublicationMode: .immediate,
            state: state,
            failureReason: failureReason,
            onEvent: onEvent
        )
    }

    private func finish(
        manifest: LearningRunManifest,
        metrics: [TrainingMetricRecord],
        convergence: ConvergenceSummary,
        finalCheckpointID: String?,
        finalCheckpointURL: URL?,
        artifactDirectory: URL,
        checkpointPublicationMode: TrainingRunConfig.CheckpointPublicationMode,
        state: LearningRunTerminalState,
        failureReason: String?,
        onEvent: (@Sendable (TrainingRunEvent) -> Void)?
    ) async -> TrainingRunResult {
        let checkpointDecision = finalizeCheckpointDecision(
            runID: manifest.runID,
            convergence: convergence,
            candidateCheckpointID: finalCheckpointID,
            candidateCheckpointURL: finalCheckpointURL,
            artifactDirectory: artifactDirectory,
            publicationMode: checkpointPublicationMode
        )
        let completedManifest = manifest.completed(
            at: Date(),
            terminalState: state,
            outputCheckpointID: finalCheckpointID,
            failureReason: failureReason
        )
        do {
            try artifactWriter.write(
                manifest: completedManifest,
                metrics: metrics,
                convergence: convergence,
                checkpointDecision: checkpointDecision,
                to: artifactDirectory
            )
        } catch {
            // Artifact failures are reflected in the returned manifest but do not erase the run outcome.
            let artifactFailureManifest = completedManifest.completed(
                at: Date(),
                terminalState: .failed,
                outputCheckpointID: finalCheckpointID,
                failureReason: "artifact-write-failed: \(error)"
            )
            let result = TrainingRunResult(
                manifest: artifactFailureManifest,
                metrics: metrics,
                convergence: convergence,
                checkpointDecision: checkpointDecision
            )
            onEvent?(.completed(result))
            return result
        }

        let result = TrainingRunResult(
            manifest: completedManifest,
            metrics: metrics,
            convergence: convergence,
            checkpointDecision: checkpointDecision
        )
        onEvent?(.completed(result))
        return result
    }

    private func finalizeCheckpointDecision(
        runID: String,
        convergence: ConvergenceSummary,
        candidateCheckpointID: String?,
        candidateCheckpointURL: URL?,
        artifactDirectory: URL,
        publicationMode: TrainingRunConfig.CheckpointPublicationMode
    ) -> CheckpointDecision {
        let initial = checkpointPolicy.decision(
            runID: runID,
            convergence: convergence,
            candidateCheckpointID: candidateCheckpointID,
            candidateCheckpointURL: candidateCheckpointURL
        )
        if publicationMode == .deferred, initial.state == .accepted {
            return CheckpointDecision(
                runID: runID,
                state: .staged,
                reason: "checkpoint-publication-deferred",
                candidateCheckpointID: candidateCheckpointID,
                candidateCheckpointURL: candidateCheckpointURL,
                publishedCheckpointURL: nil,
                decidedAt: initial.decidedAt
            )
        }
        do {
            return try checkpointRepository.publish(decision: initial, under: artifactDirectory)
        } catch {
            return CheckpointDecision(
                runID: runID,
                state: .failed,
                reason: "checkpoint-publish-failed: \(error)",
                candidateCheckpointID: candidateCheckpointID,
                candidateCheckpointURL: candidateCheckpointURL
            )
        }
    }

    private func suiteMetrics(
        runID: String,
        iteration: Int,
        output: KuyAtt1RunOutput,
        score: Double
    ) -> [TrainingMetricRecord] {
        let evaluations = output.summary.evaluations
        let total = max(evaluations.count, 1)
        let passed = evaluations.filter(\.passed).count
        let failures = evaluations.filter { !$0.passed || $0.failureReason != nil }.count
        let safetyViolation = evaluations.reduce(0.0) { partial, evaluation in
            partial + evaluation.sustainedViolationSeconds
        }
        return [
            TrainingMetricRecord(runID: runID, iteration: iteration, kind: .score, value: score),
            TrainingMetricRecord(runID: runID, iteration: iteration, kind: .passRate, value: Double(passed) / Double(total)),
            TrainingMetricRecord(runID: runID, iteration: iteration, kind: .failureRate, value: Double(failures) / Double(total)),
            TrainingMetricRecord(runID: runID, iteration: iteration, kind: .safetyViolation, value: safetyViolation),
        ]
    }

    public nonisolated static func score(from summary: ValidationSummary) -> Double {
        var score = summary.suitePassed ? 1.0 : 0.0
        if let worstOvershoot = summary.aggregate.worstOvershootDegrees {
            score -= min(1.0, worstOvershoot / 90.0) * 0.4
        }
        if let recovery = summary.aggregate.averageRecoveryTime {
            score -= min(1.0, recovery / 5.0) * 0.3
        }
        if let hf = summary.aggregate.averageHfStabilityScore {
            score += max(0.0, min(hf, 1.0)) * 0.2
        }
        return score
    }

    private func requestHash(_ request: SimulationRunRequest) -> String {
        [
            request.controller.rawValue,
            request.taskMode.rawValue,
            "\(request.cutPeriodSteps)",
            request.determinism.tier.rawValue,
            request.modelDescriptorPath,
        ].joined(separator: "|")
    }

    private func descriptorID(from request: SimulationRunRequest) -> String? {
        let trimmed = request.modelDescriptorPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func descriptorHash(from request: SimulationRunRequest) -> String? {
        descriptorID(from: request)
    }
}
