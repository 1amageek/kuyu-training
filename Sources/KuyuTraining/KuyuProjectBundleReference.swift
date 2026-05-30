import Foundation

public enum KuyuProjectBundleRole: String, Codable, Sendable, Equatable, CaseIterable {
    case source
    case best
    case latest
    case candidate
}

public struct KuyuProjectBundleCompatibility: Codable, Sendable, Equatable {
    public let robotManifestID: String
    public let observationSchemaID: String
    public let actionSchemaID: String
    public let driveCount: Int?

    public init(
        robotManifestID: String,
        observationSchemaID: String,
        actionSchemaID: String,
        driveCount: Int?
    ) {
        self.robotManifestID = robotManifestID
        self.observationSchemaID = observationSchemaID
        self.actionSchemaID = actionSchemaID
        self.driveCount = driveCount
    }
}

public struct KuyuProjectBundleReference: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let bundleID: String
    public let role: KuyuProjectBundleRole
    public let url: String
    public let contentHash: String?
    public let requiredCompatibility: KuyuProjectBundleCompatibility

    public init(
        schemaVersion: Int = KuyuProjectBundleReference.currentSchemaVersion,
        bundleID: String,
        role: KuyuProjectBundleRole,
        url: String,
        contentHash: String?,
        requiredCompatibility: KuyuProjectBundleCompatibility
    ) {
        self.schemaVersion = schemaVersion
        self.bundleID = bundleID
        self.role = role
        self.url = url
        self.contentHash = contentHash
        self.requiredCompatibility = requiredCompatibility
    }
}
