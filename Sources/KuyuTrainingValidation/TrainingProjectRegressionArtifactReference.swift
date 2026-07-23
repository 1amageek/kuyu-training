public struct TrainingProjectRegressionArtifactReference: Sendable, Codable, Equatable {
    public let kind: String
    public let path: String
    public let accepted: Bool

    public init(kind: String, path: String, accepted: Bool) {
        self.kind = kind
        self.path = path
        self.accepted = accepted
    }
}
