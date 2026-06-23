import Foundation
import KuyuTrainingContracts

public enum ReinforcementTrainingAlgorithm: String, Sendable, Codable, Equatable {
    case actorCritic
    case imagination
}

public struct ReinforcementTrainingBackendRequest: Sendable, Equatable {
    public let rolloutDatasetURL: URL
    public let sourceSnapshot: TrainingBackendSnapshot?
    public let workerCount: Int
    public let iterations: Int
    public let learningRate: Double
    public let algorithm: ReinforcementTrainingAlgorithm
    public let maxBatches: Int?
    public let workerPlan: ParallelTrainingWorkerPlan?

    public init(
        rolloutDatasetURL: URL,
        sourceSnapshot: TrainingBackendSnapshot?,
        workerCount: Int,
        iterations: Int,
        learningRate: Double,
        algorithm: ReinforcementTrainingAlgorithm,
        maxBatches: Int? = nil,
        workerPlan: ParallelTrainingWorkerPlan? = nil
    ) {
        self.rolloutDatasetURL = rolloutDatasetURL
        self.sourceSnapshot = sourceSnapshot
        self.workerCount = max(1, workerCount)
        self.iterations = max(1, iterations)
        self.learningRate = learningRate
        self.algorithm = algorithm
        self.maxBatches = maxBatches
        self.workerPlan = workerPlan
    }
}

public struct ReinforcementTrainingBackendResult: Sendable, Equatable {
    public let rewardAverage: Double
    public let finalLoss: Double?
    public let candidateCheckpointID: String?
    public let candidateCheckpointURL: URL?
    public let workerMetrics: [ReinforcementTrainingWorkerMetric]

    public init(
        rewardAverage: Double,
        finalLoss: Double? = nil,
        candidateCheckpointID: String? = nil,
        candidateCheckpointURL: URL? = nil,
        workerMetrics: [ReinforcementTrainingWorkerMetric] = []
    ) {
        self.rewardAverage = rewardAverage
        self.finalLoss = finalLoss
        self.candidateCheckpointID = candidateCheckpointID
        self.candidateCheckpointURL = candidateCheckpointURL
        self.workerMetrics = workerMetrics
    }
}

public struct ReinforcementTrainingWorkerMetric: Sendable, Codable, Equatable {
    public let workerIndex: Int
    public let snapshotID: String
    public let rolloutShardURL: URL
    public let rewardAverage: Double
    public let throughput: Double

    public init(
        workerIndex: Int,
        snapshotID: String,
        rolloutShardURL: URL,
        rewardAverage: Double,
        throughput: Double
    ) {
        self.workerIndex = workerIndex
        self.snapshotID = snapshotID
        self.rolloutShardURL = rolloutShardURL
        self.rewardAverage = rewardAverage
        self.throughput = throughput
    }
}

@MainActor
public protocol ReinforcementTrainingBackend: TrainingBackend {
    func trainReinforcement(request: ReinforcementTrainingBackendRequest) async throws -> ReinforcementTrainingBackendResult
}
