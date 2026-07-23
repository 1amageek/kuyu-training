import KuyuTrainingContracts

public struct KuyuDatasetLegacyMigrationReport: Sendable, Codable, Equatable {
    public enum Outcome: String, Sendable, Codable, Equatable {
        case migrated
        case downgradedToOffPolicy
        case rejected
    }

    public let sourceSchemaVersion: Int
    public let targetSchemaVersion: Int
    public let sourceDatasetID: String
    public let sourceDatasetDigest: String
    public let targetDatasetID: String?
    public let targetRecordKind: KuyuDatasetRecord.Kind?
    public let targetRecordsDigest: String?
    public let outcome: Outcome
    public let unavailableFacts: [String]

    public init(
        sourceSchemaVersion: Int,
        sourceDatasetID: String,
        sourceDatasetDigest: String,
        targetDatasetID: String?,
        targetRecordKind: KuyuDatasetRecord.Kind?,
        targetRecordsDigest: String?,
        outcome: Outcome,
        unavailableFacts: [String]
    ) {
        self.sourceSchemaVersion = sourceSchemaVersion
        self.targetSchemaVersion = KuyuDatasetManifest.currentSchemaVersion
        self.sourceDatasetID = sourceDatasetID
        self.sourceDatasetDigest = sourceDatasetDigest
        self.targetDatasetID = targetDatasetID
        self.targetRecordKind = targetRecordKind
        self.targetRecordsDigest = targetRecordsDigest
        self.outcome = outcome
        self.unavailableFacts = unavailableFacts
    }
}
