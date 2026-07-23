import Foundation

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
    public let miniBatchSize: Int?
    public let sourceSnapshot: TrainingBackendSnapshot?
    public let iteration: Int

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
        miniBatchSize: Int? = nil,
        sourceSnapshot: TrainingBackendSnapshot? = nil,
        iteration: Int = 0
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
        self.miniBatchSize = miniBatchSize.map { max(1, $0) }
        self.sourceSnapshot = sourceSnapshot
        self.iteration = max(0, iteration)
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

public protocol TrainingBackend: Sendable {
    func trainSupervised(request: TrainingBackendRequest) async throws -> TrainingBackendResult
}
