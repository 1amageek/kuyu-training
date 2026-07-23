public struct KuyuTrajectoryCoordinate: Sendable, Codable, Equatable {
    public let episodeID: String
    public let segmentID: String
    public let segmentIndex: Int
    public let transitionIndex: Int
    public let decisionID: String

    public init(
        episodeID: String,
        segmentID: String,
        segmentIndex: Int,
        transitionIndex: Int,
        decisionID: String
    ) {
        self.episodeID = episodeID
        self.segmentID = segmentID
        self.segmentIndex = segmentIndex
        self.transitionIndex = transitionIndex
        self.decisionID = decisionID
    }
}
