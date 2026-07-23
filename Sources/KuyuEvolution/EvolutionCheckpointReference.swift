import Foundation

public struct EvolutionCheckpointReference: Sendable, Codable, Equatable {
    public let checkpointID: String
    public let checkpointURL: URL
    public let sha256Digest: String
    public let fileCount: Int
    public let byteCount: Int

    public init(
        checkpointID: String,
        checkpointURL: URL,
        sha256Digest: String,
        fileCount: Int,
        byteCount: Int
    ) {
        self.checkpointID = checkpointID
        self.checkpointURL = checkpointURL
        self.sha256Digest = sha256Digest
        self.fileCount = fileCount
        self.byteCount = byteCount
    }
}
