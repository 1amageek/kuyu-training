import Foundation

public struct TrainingBackendSnapshot: Sendable, Codable, Equatable {
    public let snapshotID: String
    public let checkpointID: String?
    public let checkpointURL: URL?
    public let robotManifestID: String?
    public let robotManifestHash: String?
    public let configHash: String?
    public let createdAt: Date

    public init(
        snapshotID: String,
        checkpointID: String? = nil,
        checkpointURL: URL? = nil,
        robotManifestID: String? = nil,
        robotManifestHash: String? = nil,
        configHash: String? = nil,
        createdAt: Date = Date()
    ) {
        self.snapshotID = snapshotID
        self.checkpointID = checkpointID
        self.checkpointURL = checkpointURL
        self.robotManifestID = robotManifestID
        self.robotManifestHash = robotManifestHash
        self.configHash = configHash
        self.createdAt = createdAt
    }
}

public protocol SnapshotTrainingBackend: TrainingBackend {
    func makeSnapshot(for manifest: LearningRunManifest) async throws -> TrainingBackendSnapshot
}
