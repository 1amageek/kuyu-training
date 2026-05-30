import Foundation

public struct SnapshotIdentity: Sendable, Codable, Equatable, Hashable {
    public let policyID: String
    public let snapshotID: String
    public let robotManifestID: String?
    public let configHash: String?

    public init(
        policyID: String,
        snapshotID: String,
        robotManifestID: String? = nil,
        configHash: String? = nil
    ) {
        self.policyID = policyID
        self.snapshotID = snapshotID
        self.robotManifestID = robotManifestID
        self.configHash = configHash
    }
}

public struct WorkerSnapshot: Sendable, Codable, Equatable {
    public let identity: SnapshotIdentity
    public let workerIndex: Int
    public let checkpointURL: URL

    public init(
        identity: SnapshotIdentity,
        workerIndex: Int,
        checkpointURL: URL
    ) {
        self.identity = identity
        self.workerIndex = workerIndex
        self.checkpointURL = checkpointURL
    }
}

public struct SnapshotLease: Sendable, Codable, Equatable {
    public let snapshot: WorkerSnapshot
    public let leasedAt: Date
    public let expiresAt: Date?

    public init(
        snapshot: WorkerSnapshot,
        leasedAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.snapshot = snapshot
        self.leasedAt = leasedAt
        self.expiresAt = expiresAt
    }
}

public protocol SnapshotProviding: Sendable {
    func leaseSnapshot(workerIndex: Int) async throws -> SnapshotLease
}
