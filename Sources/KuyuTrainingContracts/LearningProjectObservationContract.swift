import Foundation

public struct LearningProjectObservationChannel: Codable, Sendable, Equatable {
    public let index: Int
    public let name: String
    public let unit: String?
    public let isStateChannel: Bool
    public let isStressable: Bool

    public init(
        index: Int,
        name: String,
        unit: String?,
        isStateChannel: Bool,
        isStressable: Bool
    ) {
        self.index = index
        self.name = name
        self.unit = unit
        self.isStateChannel = isStateChannel
        self.isStressable = isStressable
    }
}

public struct LearningProjectObservationContract: Codable, Sendable, Equatable {
    public let schemaID: String
    public let channelCount: Int
    public let channels: [LearningProjectObservationChannel]

    public init(
        schemaID: String,
        channelCount: Int,
        channels: [LearningProjectObservationChannel]
    ) {
        self.schemaID = schemaID
        self.channelCount = channelCount
        self.channels = channels
    }
}
