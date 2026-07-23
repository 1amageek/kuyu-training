import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

extension TrainingRunOrchestrator {
    struct IterationTrainingResult: Sendable, Equatable {
        let metrics: [TrainingMetricRecord]
        let candidateCheckpointID: String?
        let candidateCheckpointURL: URL?
    }

    func train(
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
                miniBatchSize: trainingTemplate.miniBatchSize,
                sourceSnapshot: sourceSnapshot,
                iteration: iteration
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
            to: mixedDirectory,
            datasetContract: TrainingDatasetContract()
        )
        return mixedDirectory
    }
}
