public struct KuyuDatasetManifest: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 7

    public enum RecordEncoding: String, Sendable, Codable, Equatable {
        case jsonLines
    }

    public let schemaVersion: Int
    public let descriptor: KuyuDatasetDescriptor
    public let recordEncoding: RecordEncoding
    public let recordCount: UInt64
    public let recordsDigest: String

    public init(
        descriptor: KuyuDatasetDescriptor,
        recordCount: UInt64,
        recordsDigest: String,
        schemaVersion: Int = KuyuDatasetManifest.currentSchemaVersion,
        recordEncoding: RecordEncoding = .jsonLines
    ) {
        self.schemaVersion = schemaVersion
        self.descriptor = descriptor
        self.recordEncoding = recordEncoding
        self.recordCount = recordCount
        self.recordsDigest = recordsDigest
    }
}
