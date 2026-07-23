import Foundation

public struct TrainingProjectDatasetLineageRecord: Sendable, Codable, Equatable {
    public let datasetID: String
    public let scenarioID: String
    public let seed: UInt64
    public let recordCount: Int
    public let configHash: String
    public let rewardDescriptorID: String?
    public let rewardDescriptorVersion: String?
    public let rewardDescriptorConfigHash: String?
    public let suiteVersion: String?

    public init(
        datasetID: String,
        scenarioID: String,
        seed: UInt64,
        recordCount: Int,
        configHash: String,
        rewardDescriptorID: String?,
        rewardDescriptorVersion: String?,
        rewardDescriptorConfigHash: String?,
        suiteVersion: String?
    ) {
        self.datasetID = datasetID
        self.scenarioID = scenarioID
        self.seed = seed
        self.recordCount = recordCount
        self.configHash = configHash
        self.rewardDescriptorID = rewardDescriptorID
        self.rewardDescriptorVersion = rewardDescriptorVersion
        self.rewardDescriptorConfigHash = rewardDescriptorConfigHash
        self.suiteVersion = suiteVersion
    }

    public init(metadata: TrainingDatasetMetadata) {
        let trimmedEpisodeID = metadata.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let datasetID: String
        if let trimmedEpisodeID, !trimmedEpisodeID.isEmpty {
            datasetID = trimmedEpisodeID
        } else {
            datasetID = "\(metadata.scenarioId):\(metadata.seed)"
        }
        self.init(
            datasetID: datasetID,
            scenarioID: metadata.scenarioId,
            seed: metadata.seed,
            recordCount: metadata.recordCount,
            configHash: metadata.configHash,
            rewardDescriptorID: metadata.rewardDescriptor?.id,
            rewardDescriptorVersion: metadata.rewardDescriptor?.version,
            rewardDescriptorConfigHash: metadata.rewardDescriptor?.configHash,
            suiteVersion: metadata.provenance?.suiteVersion
        )
    }
}
