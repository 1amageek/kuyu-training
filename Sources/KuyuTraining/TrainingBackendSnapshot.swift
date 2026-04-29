import Foundation

public struct TrainingBackendSnapshot: Sendable, Codable, Equatable {
    public let snapshotID: String
    public let checkpointID: String?
    public let checkpointURL: URL?
    public let descriptorID: String?
    public let configHash: String?
    public let createdAt: Date

    public init(
        snapshotID: String,
        checkpointID: String? = nil,
        checkpointURL: URL? = nil,
        descriptorID: String? = nil,
        configHash: String? = nil,
        createdAt: Date = Date()
    ) {
        self.snapshotID = snapshotID
        self.checkpointID = checkpointID
        self.checkpointURL = checkpointURL
        self.descriptorID = descriptorID
        self.configHash = configHash
        self.createdAt = createdAt
    }
}

@MainActor
public protocol SnapshotTrainingBackend: TrainingBackend {
    func makeSnapshot(for manifest: LearningRunManifest) async throws -> TrainingBackendSnapshot
}
