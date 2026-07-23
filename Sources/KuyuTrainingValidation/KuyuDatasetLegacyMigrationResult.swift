import KuyuTrainingContracts

public enum KuyuDatasetLegacyMigrationResult: Sendable, Equatable {
    case migrated(report: KuyuDatasetLegacyMigrationReport, manifest: KuyuDatasetManifest)
    case downgradedToOffPolicy(report: KuyuDatasetLegacyMigrationReport, manifest: KuyuDatasetManifest)
    case rejected(report: KuyuDatasetLegacyMigrationReport)

    public var report: KuyuDatasetLegacyMigrationReport {
        switch self {
        case .migrated(let report, _): report
        case .downgradedToOffPolicy(let report, _): report
        case .rejected(let report): report
        }
    }
}
