import Foundation
import KuyuCore
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public struct TrainingDatasetContract: Sendable, Equatable {
    public let expectedRewardDescriptor: RewardDescriptor?
    public let expectedTaskReference: TrainingTaskReferenceMetadata?
    public let requiresTerminalFacts: Bool
    public let allowedSchemaVersions: Set<Int>

    public init(
        expectedRewardDescriptor: RewardDescriptor? = nil,
        expectedTaskReference: TrainingTaskReferenceMetadata? = nil,
        requiresTerminalFacts: Bool = true,
        allowedSchemaVersions: Set<Int> = [TrainingDatasetMetadata.currentSchemaVersion]
    ) {
        self.expectedRewardDescriptor = expectedRewardDescriptor
        self.expectedTaskReference = expectedTaskReference
        self.requiresTerminalFacts = requiresTerminalFacts
        self.allowedSchemaVersions = allowedSchemaVersions
    }
}

public struct TrainingDatasetContractValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable {
        case unsupportedSchemaVersion(found: Int, allowed: [Int])
        case recordCountMismatch(expected: Int, actual: Int)
        case missingRewardDescriptor
        case rewardDescriptorMismatch(expected: RewardDescriptor, actual: RewardDescriptor)
        case missingTaskReference
        case taskReferenceMismatch(expected: TrainingTaskReferenceMetadata, actual: TrainingTaskReferenceMetadata)
        case emptyDatasetRequiresTerminalFacts
        case missingTerminalFacts
        case finalRecordTerminalMismatch(
            metadataDone: Bool,
            metadataTruncated: Bool,
            recordDone: Bool?,
            recordTruncated: Bool?
        )
        case terminalDatasetRequiresZeroContinueValue(actual: Double?)
    }

    public init() {}

    public func loadAndValidate(
        from directory: URL,
        against contract: TrainingDatasetContract = TrainingDatasetContract()
    ) throws -> TrainingDataset {
        let dataset = try TrainingDataset.load(from: directory)
        try validate(dataset, against: contract)
        return dataset
    }

    public func validate(
        _ dataset: TrainingDataset,
        against contract: TrainingDatasetContract
    ) throws {
        guard contract.allowedSchemaVersions.contains(dataset.metadata.schemaVersion) else {
            throw ValidationError.unsupportedSchemaVersion(
                found: dataset.metadata.schemaVersion,
                allowed: Array(contract.allowedSchemaVersions).sorted()
            )
        }

        guard dataset.metadata.recordCount == dataset.records.count else {
            throw ValidationError.recordCountMismatch(
                expected: dataset.metadata.recordCount,
                actual: dataset.records.count
            )
        }

        if let expected = contract.expectedRewardDescriptor {
            guard let actual = dataset.metadata.rewardDescriptor else {
                throw ValidationError.missingRewardDescriptor
            }
            guard actual == expected else {
                throw ValidationError.rewardDescriptorMismatch(expected: expected, actual: actual)
            }
        }

        if let expected = contract.expectedTaskReference {
            guard let actual = dataset.metadata.taskReference else {
                throw ValidationError.missingTaskReference
            }
            guard actual == expected else {
                throw ValidationError.taskReferenceMismatch(expected: expected, actual: actual)
            }
        }

        if contract.requiresTerminalFacts {
            try validateTerminalFacts(dataset)
        }
    }

    private func validateTerminalFacts(_ dataset: TrainingDataset) throws {
        guard let metadataDone = dataset.metadata.done,
              let metadataTruncated = dataset.metadata.truncated,
              dataset.metadata.terminalReason != nil else {
            throw ValidationError.missingTerminalFacts
        }

        guard let finalRecord = dataset.records.last else {
            throw ValidationError.emptyDatasetRequiresTerminalFacts
        }

        guard finalRecord.done == metadataDone,
              finalRecord.truncated == metadataTruncated else {
            throw ValidationError.finalRecordTerminalMismatch(
                metadataDone: metadataDone,
                metadataTruncated: metadataTruncated,
                recordDone: finalRecord.done,
                recordTruncated: finalRecord.truncated
            )
        }

        if metadataDone || metadataTruncated {
            guard finalRecord.continueValue == 0.0 else {
                throw ValidationError.terminalDatasetRequiresZeroContinueValue(actual: finalRecord.continueValue)
            }
        }
    }
}
