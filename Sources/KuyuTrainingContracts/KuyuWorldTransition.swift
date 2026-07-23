public struct KuyuWorldTransition: Sendable, Codable, Equatable {
    public struct Event: Sendable, Codable, Equatable {
        public let id: String
        public let physicsTickOffset: UInt64
        public let values: [Double]

        public init(id: String, physicsTickOffset: UInt64, values: [Double]) {
            self.id = id
            self.physicsTickOffset = physicsTickOffset
            self.values = values
        }
    }

    public let coordinate: KuyuTrajectoryCoordinate
    public let sourceState: KuyuControlTransition.StateFacts
    public let actuatorCommand: KuyuControlTransition.ActuatorCommand
    public let events: [Event]
    public let outcomeState: KuyuControlTransition.StateFacts
    public let interval: KuyuControlInterval
    public let boundary: KuyuTrajectoryBoundary

    public init(
        coordinate: KuyuTrajectoryCoordinate,
        sourceState: KuyuControlTransition.StateFacts,
        actuatorCommand: KuyuControlTransition.ActuatorCommand,
        events: [Event],
        outcomeState: KuyuControlTransition.StateFacts,
        interval: KuyuControlInterval,
        boundary: KuyuTrajectoryBoundary
    ) {
        self.coordinate = coordinate
        self.sourceState = sourceState
        self.actuatorCommand = actuatorCommand
        self.events = events
        self.outcomeState = outcomeState
        self.interval = interval
        self.boundary = boundary
    }
}
