import KuyuTrainingContracts

public struct KuyuDatasetReadSummary: Sendable, Equatable {
    public let manifest: KuyuDatasetManifest
    public let observedManifestDigest: String
    public let observedRecordCount: UInt64
    public let observedRecordsDigest: String

    public init(
        manifest: KuyuDatasetManifest,
        observedManifestDigest: String,
        observedRecordCount: UInt64,
        observedRecordsDigest: String
    ) {
        self.manifest = manifest
        self.observedManifestDigest = observedManifestDigest
        self.observedRecordCount = observedRecordCount
        self.observedRecordsDigest = observedRecordsDigest
    }
}
