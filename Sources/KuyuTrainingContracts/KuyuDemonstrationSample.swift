public struct KuyuDemonstrationSample: Sendable, Codable, Equatable {
    public let coordinate: KuyuTrajectoryCoordinate
    public let observation: KuyuControlTransition.Observation
    public let stateFacts: KuyuControlTransition.StateFacts
    public let teacherAction: KuyuControlTransition.PolicyAction
    public let teacherID: String

    public init(
        coordinate: KuyuTrajectoryCoordinate,
        observation: KuyuControlTransition.Observation,
        stateFacts: KuyuControlTransition.StateFacts,
        teacherAction: KuyuControlTransition.PolicyAction,
        teacherID: String
    ) {
        self.coordinate = coordinate
        self.observation = observation
        self.stateFacts = stateFacts
        self.teacherAction = teacherAction
        self.teacherID = teacherID
    }
}
