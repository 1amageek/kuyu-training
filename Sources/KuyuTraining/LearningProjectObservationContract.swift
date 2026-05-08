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

    public static func referenceQuadrotorLift() -> LearningProjectObservationContract {
        LearningProjectObservationContract(
            schemaID: "reference-quadrotor-lift-8ch-v1",
            channelCount: 8,
            channels: [
                LearningProjectObservationChannel(index: 0, name: "gyroX", unit: "rad/s", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 1, name: "gyroY", unit: "rad/s", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 2, name: "gyroZ", unit: "rad/s", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 3, name: "accelX", unit: "m/s^2", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 4, name: "accelY", unit: "m/s^2", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 5, name: "accelZ", unit: "m/s^2", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 6, name: "altitudeZ", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 7, name: "verticalVelocityZ", unit: "m/s", isStateChannel: true, isStressable: true)
            ]
        )
    }
}
