public struct KuyuControlInterval: Sendable, Codable, Equatable {
    public let startTime: Double
    public let endTime: Double
    public let actualDuration: Double
    public let physicsTickCount: UInt64

    public init(
        startTime: Double,
        endTime: Double,
        actualDuration: Double,
        physicsTickCount: UInt64
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.actualDuration = actualDuration
        self.physicsTickCount = physicsTickCount
    }
}
