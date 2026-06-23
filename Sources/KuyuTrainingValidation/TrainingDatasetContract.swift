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
        case negativeMetadataCount(field: String, value: Int)
        case nonPositiveTimeStep(Double)
        case nonFiniteMetadataValue(field: String, value: Double)
        case nonFiniteRecordValue(recordIndex: Int, field: String, value: Double)
        case nonFiniteRecordVectorValue(recordIndex: Int, field: String, valueIndex: Int, value: Double)
        case nonMonotonicRecordTime(recordIndex: Int, previous: Double, current: Double)
        case sensorChannelOutOfRange(recordIndex: Int, channelIndex: UInt32, channelCount: Int)
        case driveIntentOutOfRange(recordIndex: Int, driveIndex: UInt32, driveCount: Int)
        case reflexCorrectionOutOfRange(recordIndex: Int, driveIndex: UInt32, driveCount: Int)
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

        try validateMetadataShape(dataset.metadata)

        guard dataset.metadata.recordCount == dataset.records.count else {
            throw ValidationError.recordCountMismatch(
                expected: dataset.metadata.recordCount,
                actual: dataset.records.count
            )
        }

        try validateRecordPayloads(dataset)

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

    private func validateMetadataShape(_ metadata: TrainingDatasetMetadata) throws {
        guard metadata.channelCount >= 0 else {
            throw ValidationError.negativeMetadataCount(field: "channelCount", value: metadata.channelCount)
        }
        guard metadata.driveCount >= 0 else {
            throw ValidationError.negativeMetadataCount(field: "driveCount", value: metadata.driveCount)
        }
        guard metadata.recordCount >= 0 else {
            throw ValidationError.negativeMetadataCount(field: "recordCount", value: metadata.recordCount)
        }
        guard metadata.timeStep.isFinite else {
            throw ValidationError.nonFiniteMetadataValue(field: "timeStep", value: metadata.timeStep)
        }
        guard metadata.timeStep > 0 else {
            throw ValidationError.nonPositiveTimeStep(metadata.timeStep)
        }
        if let failureTime = metadata.failureTime {
            try validateFiniteMetadataValue(failureTime, field: "failureTime")
        }
        if let rewardSum = metadata.rewardSum {
            try validateFiniteMetadataValue(rewardSum, field: "rewardSum")
        }
    }

    private func validateRecordPayloads(_ dataset: TrainingDataset) throws {
        var previousTime: Double?
        for (recordIndex, record) in dataset.records.enumerated() {
            try validateFiniteRecordValue(record.time, recordIndex: recordIndex, field: "time")
            if let previous = previousTime, record.time < previous {
                throw ValidationError.nonMonotonicRecordTime(
                    recordIndex: recordIndex,
                    previous: previous,
                    current: record.time
                )
            }
            previousTime = record.time

            for sensor in record.sensors {
                guard Int(sensor.channelIndex) < dataset.metadata.channelCount else {
                    throw ValidationError.sensorChannelOutOfRange(
                        recordIndex: recordIndex,
                        channelIndex: sensor.channelIndex,
                        channelCount: dataset.metadata.channelCount
                    )
                }
                try validateFiniteRecordValue(sensor.value, recordIndex: recordIndex, field: "sensor.value")
                try validateFiniteRecordValue(sensor.timestamp, recordIndex: recordIndex, field: "sensor.timestamp")
            }

            for driveIntent in record.driveIntents {
                guard Int(driveIntent.driveIndex) < dataset.metadata.driveCount else {
                    throw ValidationError.driveIntentOutOfRange(
                        recordIndex: recordIndex,
                        driveIndex: driveIntent.driveIndex,
                        driveCount: dataset.metadata.driveCount
                    )
                }
                try validateFiniteRecordValue(driveIntent.value, recordIndex: recordIndex, field: "driveIntent.value")
                try validateFiniteRecordVectorValue(
                    driveIntent.parameters,
                    recordIndex: recordIndex,
                    field: "driveIntent.parameters"
                )
            }

            for correction in record.reflexCorrections {
                guard Int(correction.driveIndex) < dataset.metadata.driveCount else {
                    throw ValidationError.reflexCorrectionOutOfRange(
                        recordIndex: recordIndex,
                        driveIndex: correction.driveIndex,
                        driveCount: dataset.metadata.driveCount
                    )
                }
                try validateFiniteRecordValue(correction.clamp, recordIndex: recordIndex, field: "reflexCorrection.clamp")
                try validateFiniteRecordValue(correction.damping, recordIndex: recordIndex, field: "reflexCorrection.damping")
                try validateFiniteRecordValue(correction.delta, recordIndex: recordIndex, field: "reflexCorrection.delta")
            }

            if let physicsState = record.physicsState {
                try validateFiniteRecordVectorValue(physicsState, recordIndex: recordIndex, field: "physicsState")
            }
            if let actualState = record.actualState {
                try validateFiniteRecordVectorValue(actualState, recordIndex: recordIndex, field: "actualState")
            }
            if let actionValues = record.actionValues {
                try validateFiniteRecordVectorValue(actionValues, recordIndex: recordIndex, field: "actionValues")
            }
            if let continueValue = record.continueValue {
                try validateFiniteRecordValue(continueValue, recordIndex: recordIndex, field: "continueValue")
            }
            if let reward = record.reward {
                try validateFiniteRecordValue(reward, recordIndex: recordIndex, field: "reward")
            }
            if let cost = record.cost {
                try validateFiniteRecordValue(cost, recordIndex: recordIndex, field: "cost")
            }
        }
    }

    private func validateFiniteMetadataValue(_ value: Double, field: String) throws {
        guard value.isFinite else {
            throw ValidationError.nonFiniteMetadataValue(field: field, value: value)
        }
    }

    private func validateFiniteRecordValue(_ value: Double, recordIndex: Int, field: String) throws {
        guard value.isFinite else {
            throw ValidationError.nonFiniteRecordValue(recordIndex: recordIndex, field: field, value: value)
        }
    }

    private func validateFiniteRecordVectorValue(_ values: [Double], recordIndex: Int, field: String) throws {
        for (valueIndex, value) in values.enumerated() {
            guard value.isFinite else {
                throw ValidationError.nonFiniteRecordVectorValue(
                    recordIndex: recordIndex,
                    field: field,
                    valueIndex: valueIndex,
                    value: value
                )
            }
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
