import Foundation

public struct TrainingDatasetCurationPolicyValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable {
        case emptyPolicyID
        case invalidMinimumDatasetCount(Int)
        case invalidMinimumTotalRecordCount(Int)
        case invalidMinimumRecordCountPerDataset(Int)
        case emptyRequiredScenarioID
        case duplicateRequiredScenarioID(String)
        case emptyAllowedDeterminismTier
        case duplicateAllowedDeterminismTier(String)
        case emptyDatasets
        case datasetCountBelowMinimum(actual: Int, minimum: Int)
        case totalRecordCountBelowMinimum(actual: Int, minimum: Int)
        case datasetRecordCountBelowMinimum(datasetID: String, actual: Int, minimum: Int)
        case missingRequiredScenarioID(String)
        case datasetDeterminismTierNotAllowed(datasetID: String, tier: String, allowed: [String])
        case datasetChannelCountMismatch(datasetID: String, actual: Int, expected: Int)
        case datasetDriveCountMismatch(datasetID: String, actual: Int, expected: Int)
        case missingRewardDescriptor(datasetID: String)
        case missingProvenance(datasetID: String)
        case projectEvidenceCannotValidateRawMetadataRequirement(String)
    }

    public init() {}

    public func validate(
        metadata: [TrainingDatasetMetadata],
        policy: TrainingDatasetCurationPolicy
    ) throws -> TrainingDatasetCurationReport {
        try validatePolicy(policy)
        guard !metadata.isEmpty else {
            throw ValidationError.emptyDatasets
        }
        let records = metadata.map(DatasetRecord.init(metadata:))
        try validateCommon(records: records, policy: policy)
        try validateRawMetadata(metadata, policy: policy)
        return makeReport(records: records, policy: policy)
    }

    public func validate(
        projectEvidencePack pack: TrainingProjectEvidencePack,
        policy: TrainingDatasetCurationPolicy
    ) throws -> TrainingDatasetCurationReport {
        try validatePolicy(policy)
        guard !pack.datasets.isEmpty else {
            throw ValidationError.emptyDatasets
        }
        try rejectRawMetadataOnlyRequirements(policy)
        let records = pack.datasets.map(DatasetRecord.init(lineage:))
        try validateCommon(records: records, policy: policy)
        return makeReport(records: records, policy: policy)
    }

    private func validatePolicy(_ policy: TrainingDatasetCurationPolicy) throws {
        guard !policy.policyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyPolicyID
        }
        guard policy.minimumDatasetCount > 0 else {
            throw ValidationError.invalidMinimumDatasetCount(policy.minimumDatasetCount)
        }
        guard policy.minimumTotalRecordCount > 0 else {
            throw ValidationError.invalidMinimumTotalRecordCount(policy.minimumTotalRecordCount)
        }
        guard policy.minimumRecordCountPerDataset > 0 else {
            throw ValidationError.invalidMinimumRecordCountPerDataset(policy.minimumRecordCountPerDataset)
        }
        var requiredScenarios: Set<String> = []
        for scenarioID in policy.requiredScenarioIDs {
            let trimmed = scenarioID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ValidationError.emptyRequiredScenarioID
            }
            guard requiredScenarios.insert(trimmed).inserted else {
                throw ValidationError.duplicateRequiredScenarioID(trimmed)
            }
        }
        var tiers: Set<String> = []
        for tier in policy.allowedDeterminismTiers {
            let trimmed = tier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ValidationError.emptyAllowedDeterminismTier
            }
            guard tiers.insert(trimmed).inserted else {
                throw ValidationError.duplicateAllowedDeterminismTier(trimmed)
            }
        }
    }

    private func rejectRawMetadataOnlyRequirements(
        _ policy: TrainingDatasetCurationPolicy
    ) throws {
        if !policy.allowedDeterminismTiers.isEmpty {
            throw ValidationError.projectEvidenceCannotValidateRawMetadataRequirement("allowedDeterminismTiers")
        }
        if policy.expectedChannelCount != nil {
            throw ValidationError.projectEvidenceCannotValidateRawMetadataRequirement("expectedChannelCount")
        }
        if policy.expectedDriveCount != nil {
            throw ValidationError.projectEvidenceCannotValidateRawMetadataRequirement("expectedDriveCount")
        }
    }

    private func validateCommon(
        records: [DatasetRecord],
        policy: TrainingDatasetCurationPolicy
    ) throws {
        guard records.count >= policy.minimumDatasetCount else {
            throw ValidationError.datasetCountBelowMinimum(
                actual: records.count,
                minimum: policy.minimumDatasetCount
            )
        }
        let totalRecordCount = records.reduce(0) { $0 + $1.recordCount }
        guard totalRecordCount >= policy.minimumTotalRecordCount else {
            throw ValidationError.totalRecordCountBelowMinimum(
                actual: totalRecordCount,
                minimum: policy.minimumTotalRecordCount
            )
        }
        for record in records {
            guard record.recordCount >= policy.minimumRecordCountPerDataset else {
                throw ValidationError.datasetRecordCountBelowMinimum(
                    datasetID: record.datasetID,
                    actual: record.recordCount,
                    minimum: policy.minimumRecordCountPerDataset
                )
            }
            if policy.requiresRewardDescriptor {
                guard record.hasRewardDescriptor else {
                    throw ValidationError.missingRewardDescriptor(datasetID: record.datasetID)
                }
            }
            if policy.requiresProvenance {
                guard record.hasProvenance else {
                    throw ValidationError.missingProvenance(datasetID: record.datasetID)
                }
            }
        }
        let scenarioIDs = Set(records.map(\.scenarioID))
        for scenarioID in policy.requiredScenarioIDs where !scenarioIDs.contains(scenarioID) {
            throw ValidationError.missingRequiredScenarioID(scenarioID)
        }
    }

    private func validateRawMetadata(
        _ metadata: [TrainingDatasetMetadata],
        policy: TrainingDatasetCurationPolicy
    ) throws {
        for item in metadata {
            let datasetID = DatasetRecord.datasetID(metadata: item)
            if !policy.allowedDeterminismTiers.isEmpty,
               !policy.allowedDeterminismTiers.contains(item.determinismTier) {
                throw ValidationError.datasetDeterminismTierNotAllowed(
                    datasetID: datasetID,
                    tier: item.determinismTier,
                    allowed: policy.allowedDeterminismTiers
                )
            }
            if let expected = policy.expectedChannelCount,
               item.channelCount != expected {
                throw ValidationError.datasetChannelCountMismatch(
                    datasetID: datasetID,
                    actual: item.channelCount,
                    expected: expected
                )
            }
            if let expected = policy.expectedDriveCount,
               item.driveCount != expected {
                throw ValidationError.datasetDriveCountMismatch(
                    datasetID: datasetID,
                    actual: item.driveCount,
                    expected: expected
                )
            }
        }
    }

    private func makeReport(
        records: [DatasetRecord],
        policy: TrainingDatasetCurationPolicy
    ) -> TrainingDatasetCurationReport {
        TrainingDatasetCurationReport(
            policyID: policy.policyID,
            accepted: true,
            datasetIDs: records.map(\.datasetID).sorted(),
            scenarioIDs: Array(Set(records.map(\.scenarioID))).sorted(),
            datasetCount: records.count,
            totalRecordCount: records.reduce(0) { $0 + $1.recordCount },
            minimumDatasetCount: policy.minimumDatasetCount,
            minimumTotalRecordCount: policy.minimumTotalRecordCount,
            minimumRecordCountPerDataset: policy.minimumRecordCountPerDataset
        )
    }
}

private struct DatasetRecord: Sendable {
    let datasetID: String
    let scenarioID: String
    let recordCount: Int
    let hasRewardDescriptor: Bool
    let hasProvenance: Bool

    init(metadata: TrainingDatasetMetadata) {
        self.init(
            datasetID: Self.datasetID(metadata: metadata),
            scenarioID: metadata.scenarioId,
            recordCount: metadata.recordCount,
            hasRewardDescriptor: metadata.rewardDescriptor != nil,
            hasProvenance: metadata.provenance != nil
        )
    }

    init(lineage: TrainingProjectEvidencePack.DatasetLineageRecord) {
        self.init(
            datasetID: lineage.datasetID,
            scenarioID: lineage.scenarioID,
            recordCount: lineage.recordCount,
            hasRewardDescriptor: lineage.rewardDescriptorID != nil
                && lineage.rewardDescriptorVersion != nil
                && lineage.rewardDescriptorConfigHash != nil,
            hasProvenance: lineage.suiteVersion != nil
        )
    }

    init(
        datasetID: String,
        scenarioID: String,
        recordCount: Int,
        hasRewardDescriptor: Bool,
        hasProvenance: Bool
    ) {
        self.datasetID = datasetID
        self.scenarioID = scenarioID
        self.recordCount = recordCount
        self.hasRewardDescriptor = hasRewardDescriptor
        self.hasProvenance = hasProvenance
    }

    static func datasetID(metadata: TrainingDatasetMetadata) -> String {
        let trimmedEpisodeID = metadata.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedEpisodeID, !trimmedEpisodeID.isEmpty {
            return trimmedEpisodeID
        }
        return "\(metadata.scenarioId):\(metadata.seed)"
    }
}
