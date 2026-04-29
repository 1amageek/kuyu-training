import Foundation

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

    public init(
        rewardAverage: Double,
        finalLoss: Double? = nil,
        candidateCheckpointID: String? = nil,
        candidateCheckpointURL: URL? = nil
    ) {
        self.rewardAverage = rewardAverage
        self.finalLoss = finalLoss
        self.candidateCheckpointID = candidateCheckpointID
        self.candidateCheckpointURL = candidateCheckpointURL
    }
}

@MainActor
public protocol ReinforcementTrainingBackend: TrainingBackend {
    func trainReinforcement(request: ReinforcementTrainingBackendRequest) async throws -> ReinforcementTrainingBackendResult
}
