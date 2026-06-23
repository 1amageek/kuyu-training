import Foundation
import KuyuCore
import KuyuPhysics
import KuyuTraining
import Testing

@Test func trainingDatasetContractValidatorAcceptsMatchingScenarioTruth() throws {
    let reward = RewardDescriptor(id: "reward", version: "1", configHash: "hash-a")
    let taskReference = TrainingTaskReferenceMetadata(
        altitudeHold: TrainingAltitudeHoldReferenceMetadata(
            targetPosition: Axis3(x: 0, y: 0, z: 2),
            tolerance: 0.2,
            referenceVerticalVelocity: 0.5
        )
    )
    let dataset = makeDataset(
        rewardDescriptor: reward,
        taskReference: taskReference,
        done: false,
        truncated: true,
        terminalReason: "time-limit"
    )

    try TrainingDatasetContractValidator().validate(
        dataset,
        against: TrainingDatasetContract(
            expectedRewardDescriptor: reward,
            expectedTaskReference: taskReference
        )
    )
}

@Test func trainingDatasetContractValidatorLoadAndValidateRejectsStaleDiskDataset() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("training-dataset-contract-\(UUID().uuidString)", isDirectory: true)
    let actual = RewardDescriptor(id: "reward", version: "1", configHash: "hash-a")
    let expected = RewardDescriptor(id: "reward", version: "2", configHash: "hash-b")
    let dataset = makeDataset(
        rewardDescriptor: actual,
        done: false,
        truncated: true,
        terminalReason: "time-limit"
    )
    try TrainingDatasetWriter().write(dataset: dataset, to: directory)

    do {
        _ = try TrainingDatasetContractValidator().loadAndValidate(
            from: directory,
            against: TrainingDatasetContract(expectedRewardDescriptor: expected)
        )
        Issue.record("Expected disk dataset reward descriptor mismatch to fail.")
    } catch TrainingDatasetContractValidator.ValidationError.rewardDescriptorMismatch(let expectedError, let actualError) {
        #expect(expectedError == expected)
        #expect(actualError == actual)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func trainingDatasetContractValidatorRejectsRewardDescriptorMismatch() throws {
    let dataset = makeDataset(
        rewardDescriptor: RewardDescriptor(id: "reward", version: "1", configHash: "hash-a"),
        done: false,
        truncated: true,
        terminalReason: "time-limit"
    )
    let expected = RewardDescriptor(id: "reward", version: "2", configHash: "hash-b")

    do {
        try TrainingDatasetContractValidator().validate(
            dataset,
            against: TrainingDatasetContract(expectedRewardDescriptor: expected)
        )
        Issue.record("Expected reward descriptor mismatch to fail.")
    } catch TrainingDatasetContractValidator.ValidationError.rewardDescriptorMismatch(let expectedError, let actual) {
        #expect(expectedError == expected)
        #expect(actual == RewardDescriptor(id: "reward", version: "1", configHash: "hash-a"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func trainingDatasetContractValidatorRejectsMissingRewardDescriptorWhenExpected() throws {
    let dataset = makeDataset(
        rewardDescriptor: nil,
        done: false,
        truncated: true,
        terminalReason: "time-limit"
    )

    do {
        try TrainingDatasetContractValidator().validate(
            dataset,
            against: TrainingDatasetContract(
                expectedRewardDescriptor: RewardDescriptor(id: "reward", version: "1", configHash: "hash")
            )
        )
        Issue.record("Expected missing reward descriptor to fail.")
    } catch TrainingDatasetContractValidator.ValidationError.missingRewardDescriptor {
        #expect(true)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func trainingDatasetContractValidatorRejectsMissingTerminalFacts() throws {
    let dataset = makeDataset(
        rewardDescriptor: nil,
        done: nil,
        truncated: nil,
        terminalReason: nil
    )

    do {
        try TrainingDatasetContractValidator().validate(dataset, against: TrainingDatasetContract())
        Issue.record("Expected missing terminal facts to fail.")
    } catch TrainingDatasetContractValidator.ValidationError.missingTerminalFacts {
        #expect(true)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func trainingDatasetContractValidatorRejectsFinalRecordTerminalMismatch() throws {
    let metadata = makeMetadata(done: true, truncated: false, terminalReason: "sustained-fall")
    let record = TrainingDatasetRecord(
        time: 0,
        sensors: [],
        driveIntents: [],
        reflexCorrections: [],
        continueValue: 0.0,
        done: false,
        truncated: false
    )
    let dataset = TrainingDataset(metadata: metadata, records: [record])

    do {
        try TrainingDatasetContractValidator().validate(dataset, against: TrainingDatasetContract())
        Issue.record("Expected final record mismatch to fail.")
    } catch TrainingDatasetContractValidator.ValidationError.finalRecordTerminalMismatch(
        let metadataDone,
        let metadataTruncated,
        let recordDone,
        let recordTruncated
    ) {
        #expect(metadataDone)
        #expect(!metadataTruncated)
        #expect(recordDone == false)
        #expect(recordTruncated == false)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func trainingDatasetContractValidatorRejectsTerminalRecordWithContinuingValue() throws {
    let metadata = makeMetadata(done: false, truncated: true, terminalReason: "time-limit")
    let record = TrainingDatasetRecord(
        time: 0,
        sensors: [],
        driveIntents: [],
        reflexCorrections: [],
        continueValue: 1.0,
        done: false,
        truncated: true
    )
    let dataset = TrainingDataset(metadata: metadata, records: [record])

    do {
        try TrainingDatasetContractValidator().validate(dataset, against: TrainingDatasetContract())
        Issue.record("Expected terminal continueValue mismatch to fail.")
    } catch TrainingDatasetContractValidator.ValidationError.terminalDatasetRequiresZeroContinueValue(let actual) {
        #expect(actual == 1.0)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func trainingDatasetContractValidatorRejectsNegativeMetadataCounts() throws {
    let dataset = TrainingDataset(
        metadata: makeMetadata(channelCount: -1, done: false, truncated: true, terminalReason: "time-limit"),
        records: [makeRecord()]
    )

    do {
        try TrainingDatasetContractValidator().validate(dataset, against: TrainingDatasetContract())
        Issue.record("Expected negative metadata count to fail.")
    } catch TrainingDatasetContractValidator.ValidationError.negativeMetadataCount(let field, let value) {
        #expect(field == "channelCount")
        #expect(value == -1)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func trainingDatasetContractValidatorRejectsNonPositiveTimeStep() throws {
    let dataset = TrainingDataset(
        metadata: makeMetadata(timeStep: 0, done: false, truncated: true, terminalReason: "time-limit"),
        records: [makeRecord()]
    )

    do {
        try TrainingDatasetContractValidator().validate(dataset, against: TrainingDatasetContract())
        Issue.record("Expected non-positive time step to fail.")
    } catch TrainingDatasetContractValidator.ValidationError.nonPositiveTimeStep(let value) {
        #expect(value == 0)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func trainingDatasetContractValidatorRejectsNonFinitePayloadValues() throws {
    let dataset = TrainingDataset(
        metadata: makeMetadata(channelCount: 1, driveCount: 1, done: false, truncated: true, terminalReason: "time-limit"),
        records: [
            makeRecord(
                sensors: [TrainingSensorSample(channelIndex: 0, value: 1, timestamp: 0)],
                driveIntents: [TrainingDriveIntent(driveIndex: 0, value: 0.1)],
                actionValues: [Double.nan]
            )
        ]
    )

    do {
        try TrainingDatasetContractValidator().validate(dataset, against: TrainingDatasetContract())
        Issue.record("Expected non-finite payload value to fail.")
    } catch TrainingDatasetContractValidator.ValidationError.nonFiniteRecordVectorValue(
        let recordIndex,
        let field,
        let valueIndex,
        let value
    ) {
        #expect(recordIndex == 0)
        #expect(field == "actionValues")
        #expect(valueIndex == 0)
        #expect(value.isNaN)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func trainingDatasetContractValidatorRejectsOutOfRangeSensorChannel() throws {
    let dataset = TrainingDataset(
        metadata: makeMetadata(channelCount: 1, done: false, truncated: true, terminalReason: "time-limit"),
        records: [
            makeRecord(sensors: [TrainingSensorSample(channelIndex: 1, value: 1, timestamp: 0)])
        ]
    )

    do {
        try TrainingDatasetContractValidator().validate(dataset, against: TrainingDatasetContract())
        Issue.record("Expected out-of-range sensor channel to fail.")
    } catch TrainingDatasetContractValidator.ValidationError.sensorChannelOutOfRange(
        let recordIndex,
        let channelIndex,
        let channelCount
    ) {
        #expect(recordIndex == 0)
        #expect(channelIndex == 1)
        #expect(channelCount == 1)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func trainingDatasetContractValidatorRejectsOutOfRangeDrivePayloads() throws {
    let dataset = TrainingDataset(
        metadata: makeMetadata(driveCount: 1, done: false, truncated: true, terminalReason: "time-limit"),
        records: [
            makeRecord(driveIntents: [TrainingDriveIntent(driveIndex: 1, value: 0.1)])
        ]
    )

    do {
        try TrainingDatasetContractValidator().validate(dataset, against: TrainingDatasetContract())
        Issue.record("Expected out-of-range drive intent to fail.")
    } catch TrainingDatasetContractValidator.ValidationError.driveIntentOutOfRange(
        let recordIndex,
        let driveIndex,
        let driveCount
    ) {
        #expect(recordIndex == 0)
        #expect(driveIndex == 1)
        #expect(driveCount == 1)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func trainingDatasetContractValidatorRejectsNonMonotonicRecordTime() throws {
    let dataset = TrainingDataset(
        metadata: makeMetadata(recordCount: 2, done: false, truncated: true, terminalReason: "time-limit"),
        records: [
            makeRecord(time: 1, continueValue: 1.0, done: false, truncated: false),
            makeRecord(time: 0, continueValue: 0.0, done: false, truncated: true)
        ]
    )

    do {
        try TrainingDatasetContractValidator().validate(dataset, against: TrainingDatasetContract())
        Issue.record("Expected non-monotonic record time to fail.")
    } catch TrainingDatasetContractValidator.ValidationError.nonMonotonicRecordTime(
        let recordIndex,
        let previous,
        let current
    ) {
        #expect(recordIndex == 1)
        #expect(previous == 1)
        #expect(current == 0)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

private func makeDataset(
    rewardDescriptor: RewardDescriptor?,
    taskReference: TrainingTaskReferenceMetadata? = nil,
    done: Bool?,
    truncated: Bool?,
    terminalReason: String?
) -> TrainingDataset {
    let metadata = makeMetadata(
        rewardDescriptor: rewardDescriptor,
        taskReference: taskReference,
        done: done,
        truncated: truncated,
        terminalReason: terminalReason
    )
    let record = TrainingDatasetRecord(
        time: 0,
        sensors: [],
        driveIntents: [],
        reflexCorrections: [],
        continueValue: 0.0,
        done: done,
        truncated: truncated
    )
    return TrainingDataset(metadata: metadata, records: [record])
}

private func makeRecord(
    time: Double = 0,
    sensors: [TrainingSensorSample] = [],
    driveIntents: [TrainingDriveIntent] = [],
    reflexCorrections: [TrainingReflexCorrection] = [],
    physicsState: [Double]? = nil,
    actualState: [Double]? = nil,
    actionValues: [Double]? = nil,
    continueValue: Double? = 0.0,
    reward: Double? = nil,
    cost: Double? = nil,
    done: Bool? = false,
    truncated: Bool? = true
) -> TrainingDatasetRecord {
    TrainingDatasetRecord(
        time: time,
        sensors: sensors,
        driveIntents: driveIntents,
        reflexCorrections: reflexCorrections,
        physicsState: physicsState,
        actualState: actualState,
        actionValues: actionValues,
        continueValue: continueValue,
        reward: reward,
        cost: cost,
        done: done,
        truncated: truncated
    )
}

private func makeMetadata(
    rewardDescriptor: RewardDescriptor? = nil,
    taskReference: TrainingTaskReferenceMetadata? = nil,
    timeStep: Double = 0.005,
    channelCount: Int = 0,
    driveCount: Int = 0,
    recordCount: Int = 1,
    done: Bool?,
    truncated: Bool?,
    terminalReason: String?
) -> TrainingDatasetMetadata {
    TrainingDatasetMetadata(
        scenarioId: "scenario",
        seed: 1,
        timeStep: timeStep,
        determinismTier: "tier0",
        configHash: "config",
        channelCount: channelCount,
        driveCount: driveCount,
        recordCount: recordCount,
        done: done,
        truncated: truncated,
        terminalReason: terminalReason,
        rewardDescriptor: rewardDescriptor,
        taskReference: taskReference
    )
}
