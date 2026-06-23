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

private func makeMetadata(
    rewardDescriptor: RewardDescriptor? = nil,
    taskReference: TrainingTaskReferenceMetadata? = nil,
    done: Bool?,
    truncated: Bool?,
    terminalReason: String?
) -> TrainingDatasetMetadata {
    TrainingDatasetMetadata(
        scenarioId: "scenario",
        seed: 1,
        timeStep: 0.005,
        determinismTier: "tier0",
        configHash: "config",
        channelCount: 0,
        driveCount: 0,
        recordCount: 1,
        done: done,
        truncated: truncated,
        terminalReason: terminalReason,
        rewardDescriptor: rewardDescriptor,
        taskReference: taskReference
    )
}
