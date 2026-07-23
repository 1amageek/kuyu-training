import Foundation

public enum ModelBundleReferenceKind: String, Sendable, Codable, Equatable, CaseIterable {
    case source
    case incumbent
    case candidate
    case accepted
    case archived
}

public struct ModelBundleReference: Sendable, Codable, Equatable {
    public let bundleID: String
    public let kind: ModelBundleReferenceKind
    public let url: URL
    public let provenanceURL: URL?
    public let contentHash: String?
    public let robotManifestID: String?
    public let observationSchemaID: String?
    public let actionSchemaID: String?

    public init(
        bundleID: String,
        kind: ModelBundleReferenceKind,
        url: URL,
        provenanceURL: URL? = nil,
        contentHash: String? = nil,
        robotManifestID: String? = nil,
        observationSchemaID: String? = nil,
        actionSchemaID: String? = nil
    ) {
        self.bundleID = bundleID
        self.kind = kind
        self.url = url
        self.provenanceURL = provenanceURL
        self.contentHash = contentHash
        self.robotManifestID = robotManifestID
        self.observationSchemaID = observationSchemaID
        self.actionSchemaID = actionSchemaID
    }
}
