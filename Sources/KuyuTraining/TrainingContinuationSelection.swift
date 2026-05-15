import Foundation

public enum TrainingContinuationCheckpointSource: String, Codable, Sendable, Equatable {
    case bestCandidate
    case finalCheckpoint
}

public struct TrainingContinuationSelection: Codable, Sendable, Equatable {
    public let previousArtifactRoot: URL
    public let checkpointURL: URL
    public let source: TrainingContinuationCheckpointSource
    public let candidateID: String?
    public let generationIndex: Int?
    public let scalarFitness: Double?

    public init(
        previousArtifactRoot: URL,
        checkpointURL: URL,
        source: TrainingContinuationCheckpointSource,
        candidateID: String? = nil,
        generationIndex: Int? = nil,
        scalarFitness: Double? = nil
    ) {
        self.previousArtifactRoot = previousArtifactRoot
        self.checkpointURL = checkpointURL
        self.source = source
        self.candidateID = candidateID
        self.generationIndex = generationIndex
        self.scalarFitness = scalarFitness
    }
}
