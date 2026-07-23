import Foundation

public struct TrainingProbeAcceptanceReceipt: Sendable, Equatable {
    public let artifactDirectory: URL
    public let probeID: String
    public let trainingRunID: String
    public let sourceCheckpointURL: URL
    public let publishedCheckpointURL: URL
    public let datasetCount: Int
    public let scenarioRunCount: Int
    public let trainedScore: Double
    public let scoreDelta: Double

    public init(
        artifactDirectory: URL,
        probeID: String,
        trainingRunID: String,
        sourceCheckpointURL: URL,
        publishedCheckpointURL: URL,
        datasetCount: Int,
        scenarioRunCount: Int,
        trainedScore: Double,
        scoreDelta: Double
    ) {
        self.artifactDirectory = artifactDirectory
        self.probeID = probeID
        self.trainingRunID = trainingRunID
        self.sourceCheckpointURL = sourceCheckpointURL
        self.publishedCheckpointURL = publishedCheckpointURL
        self.datasetCount = datasetCount
        self.scenarioRunCount = scenarioRunCount
        self.trainedScore = trainedScore
        self.scoreDelta = scoreDelta
    }
}

