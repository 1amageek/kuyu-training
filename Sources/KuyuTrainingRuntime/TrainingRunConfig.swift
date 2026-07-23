import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public struct TrainingRunConfig: Sendable, Equatable {
    public enum EvaluationScope: String, Sendable, Codable, Equatable {
        case acceptance
        case progress
    }

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
    public internal(set) var checkpointPublicationMode: CheckpointPublicationMode
    public let datasetRefreshPolicy: TrainingDatasetRefreshPolicy
    public let evaluationScope: EvaluationScope

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
        checkpointPublicationMode: CheckpointPublicationMode = .immediate,
        datasetRefreshPolicy: TrainingDatasetRefreshPolicy = .perIteration,
        evaluationScope: EvaluationScope = .acceptance
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
        self.datasetRefreshPolicy = datasetRefreshPolicy
        self.evaluationScope = evaluationScope
    }
}
