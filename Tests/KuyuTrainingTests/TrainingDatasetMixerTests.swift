import Foundation
import KuyuCore
import KuyuTraining
import Testing

@Suite("TrainingDatasetMixer")
struct TrainingDatasetMixerTests {
    @Test func mixesSingleAndNestedDatasetRootsIntoLoadableOutput() throws {
        let root = temporaryDirectory("training-dataset-mixer")
        let single = root.appendingPathComponent("single", isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        let output = root.appendingPathComponent("mixed", isDirectory: true)
        try writeDataset(to: single, scenarioID: "single", seed: 1, recordCount: 2)
        try writeDataset(to: nested.appendingPathComponent("child-a", isDirectory: true), scenarioID: "child-a", seed: 2, recordCount: 3)
        try writeDataset(to: nested.appendingPathComponent("child-b", isDirectory: true), scenarioID: "child-b", seed: 3, recordCount: 4)

        let manifest = try TrainingDatasetMixer().mix(sources: [single, nested], to: output)

        #expect(manifest.datasetCount == 3)
        #expect(manifest.totalRecordCount == 9)
        #expect(manifest.sources.map(\.copiedDatasetCount) == [1, 2])
        let children = try FileManager.default.contentsOfDirectory(
            at: output,
            includingPropertiesForKeys: nil
        )
        let datasetDirectories = children.filter {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("meta.json").path)
        }
        #expect(datasetDirectories.count == 3)
        for directory in datasetDirectories {
            _ = try TrainingDataset.load(from: directory)
        }
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("dataset-mix-manifest.json").path))
    }

    @Test func rejectsSourcesWithoutDatasets() throws {
        let root = temporaryDirectory("training-dataset-mixer-empty")
        let source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        #expect(throws: TrainingDatasetMixer.MixError.noDatasetsFound([source.path])) {
            try TrainingDatasetMixer().mix(
                sources: [source],
                to: root.appendingPathComponent("mixed", isDirectory: true)
            )
        }
    }

    @Test func mixAcceptsDatasetsThatSatisfyContract() throws {
        let root = temporaryDirectory("training-dataset-mixer-contract")
        let source = root.appendingPathComponent("source", isDirectory: true)
        let output = root.appendingPathComponent("mixed", isDirectory: true)
        let reward = RewardDescriptor(id: "reward", version: "1", configHash: "hash-a")
        try writeDataset(
            to: source,
            scenarioID: "contract-valid",
            seed: 1,
            recordCount: 2,
            rewardDescriptor: reward,
            done: false,
            truncated: true,
            terminalReason: "time-limit"
        )

        let manifest = try TrainingDatasetMixer().mix(
            sources: [source],
            to: output,
            datasetContract: TrainingDatasetContract(expectedRewardDescriptor: reward)
        )

        #expect(manifest.datasetCount == 1)
        #expect(manifest.totalRecordCount == 2)
    }

    @Test func mixRejectsDatasetsWithoutRequiredTerminalFacts() throws {
        let root = temporaryDirectory("training-dataset-mixer-missing-terminal")
        let source = root.appendingPathComponent("source", isDirectory: true)
        let output = root.appendingPathComponent("mixed", isDirectory: true)
        try writeDataset(to: source, scenarioID: "missing-terminal", seed: 1, recordCount: 2)

        do {
            _ = try TrainingDatasetMixer().mix(
                sources: [source],
                to: output,
                datasetContract: TrainingDatasetContract()
            )
            Issue.record("Expected missing terminal facts to fail.")
        } catch TrainingDatasetMixer.MixError.datasetContractViolation(let path, let reason) {
            #expect(path == source.path)
            #expect(reason == .missingTerminalFacts)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func mixRejectsDatasetsWithStaleRewardDescriptor() throws {
        let root = temporaryDirectory("training-dataset-mixer-stale-reward")
        let source = root.appendingPathComponent("source", isDirectory: true)
        let output = root.appendingPathComponent("mixed", isDirectory: true)
        let actual = RewardDescriptor(id: "reward", version: "1", configHash: "hash-a")
        let expected = RewardDescriptor(id: "reward", version: "2", configHash: "hash-b")
        try writeDataset(
            to: source,
            scenarioID: "stale-reward",
            seed: 1,
            recordCount: 2,
            rewardDescriptor: actual,
            done: false,
            truncated: true,
            terminalReason: "time-limit"
        )

        do {
            _ = try TrainingDatasetMixer().mix(
                sources: [source],
                to: output,
                datasetContract: TrainingDatasetContract(expectedRewardDescriptor: expected)
            )
            Issue.record("Expected reward descriptor mismatch to fail.")
        } catch TrainingDatasetMixer.MixError.datasetContractViolation(let path, let reason) {
            #expect(path == source.path)
            #expect(reason == .rewardDescriptorMismatch(expected: expected, actual: actual))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func suffixBudgetKeepsLatestContiguousRecordWindows() {
        let first = makeBudgetDataset(episodeID: "first", seed: 1, recordCount: 4, rewardOffset: 0)
        let second = makeBudgetDataset(episodeID: "second", seed: 2, recordCount: 4, rewardOffset: 10)

        let limited = TrainingDatasetRecordBudgeter().limit(
            [first, second],
            maxTotalRecordCount: 5,
            selection: .suffix
        )

        #expect(limited.map(\.metadata.episodeId) == ["first", "second"])
        #expect(limited.map(\.metadata.recordCount) == [1, 4])
        #expect(limited.flatMap(\.records).map(\.time) == [0.03, 0.0, 0.01, 0.02, 0.03])
        #expect(limited[0].metadata.rewardSum == 3)
        #expect(limited[0].metadata.truncated == true)
        #expect(limited[0].metadata.terminalReason == "time-limit")
    }

    @Test func prefixBudgetClearsTerminalMetadataWhenWindowStopsBeforeTerminal() {
        let first = makeBudgetDataset(episodeID: "first", seed: 1, recordCount: 4, rewardOffset: 0)
        let second = makeBudgetDataset(episodeID: "second", seed: 2, recordCount: 4, rewardOffset: 10)

        let limited = TrainingDatasetRecordBudgeter().limit(
            [first, second],
            maxTotalRecordCount: 5,
            selection: .prefix
        )

        #expect(limited.map(\.metadata.episodeId) == ["first", "second"])
        #expect(limited.map(\.metadata.recordCount) == [4, 1])
        #expect(limited[1].metadata.rewardSum == 10)
        #expect(limited[1].metadata.done == false)
        #expect(limited[1].metadata.truncated == false)
        #expect(limited[1].metadata.terminalReason == nil)
    }

    @Test func suffixFromRecordIndexPreservesTerminalFactsAndRecomputesReward() throws {
        let dataset = makeBudgetDataset(episodeID: "windowed", seed: 3, recordCount: 5, rewardOffset: 10)

        let clipped = try #require(TrainingDatasetRecordBudgeter().suffix(
            dataset,
            startingAtRecordIndex: 2
        ))

        #expect(clipped.metadata.episodeId == "windowed")
        #expect(clipped.metadata.recordCount == 3)
        #expect(clipped.records.map(\.time) == [0.02, 0.03, 0.04])
        #expect(clipped.metadata.rewardSum == 39)
        #expect(clipped.metadata.truncated == true)
        #expect(clipped.metadata.terminalReason == "time-limit")
    }

    @Test func suffixFromRecordIndexReturnsNilWhenWindowIsEmpty() {
        let dataset = makeBudgetDataset(episodeID: "empty-window", seed: 4, recordCount: 2, rewardOffset: 0)

        let clipped = TrainingDatasetRecordBudgeter().suffix(
            dataset,
            startingAtRecordIndex: 2
        )

        #expect(clipped == nil)
    }
}

private func temporaryDirectory(_ prefix: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
}

private func writeDataset(
    to directory: URL,
    scenarioID: String,
    seed: UInt64,
    recordCount: Int,
    rewardDescriptor: RewardDescriptor? = nil,
    done: Bool? = nil,
    truncated: Bool? = nil,
    terminalReason: String? = nil
) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let metadata = TrainingDatasetMetadata(
        scenarioId: scenarioID,
        seed: seed,
        timeStep: 0.01,
        determinismTier: "tier0",
        configHash: "test",
        channelCount: 1,
        driveCount: 1,
        recordCount: recordCount,
        done: done,
        truncated: truncated,
        terminalReason: terminalReason,
        rewardDescriptor: rewardDescriptor
    )
    let records = (0..<recordCount).map { index in
        let isLast = index == recordCount - 1
        return TrainingDatasetRecord(
            time: Double(index) * 0.01,
            sensors: [TrainingSensorSample(channelIndex: 0, value: Double(index), timestamp: Double(index) * 0.01)],
            driveIntents: [TrainingDriveIntent(driveIndex: 0, value: 0.5)],
            reflexCorrections: [],
            continueValue: isLast && (done == true || truncated == true) ? 0.0 : 1.0,
            done: isLast ? done : false,
            truncated: isLast ? truncated : false
        )
    }
    let encoder = JSONEncoder()
    try encoder.encode(metadata).write(
        to: directory.appendingPathComponent("meta.json"),
        options: [.atomic]
    )
    let recordsData = try records.map { record in
        String(decoding: try encoder.encode(record), as: UTF8.self)
    }.joined(separator: "\n").appending("\n")
    try recordsData.write(
        to: directory.appendingPathComponent("records.jsonl"),
        atomically: true,
        encoding: .utf8
    )
}

private func makeBudgetDataset(
    episodeID: String,
    seed: UInt64,
    recordCount: Int,
    rewardOffset: Double
) -> TrainingDataset {
    let records = (0..<recordCount).map { index in
        TrainingDatasetRecord(
            time: Double(index) * 0.01,
            sensors: [
                TrainingSensorSample(
                    channelIndex: 0,
                    value: Double(index),
                    timestamp: Double(index) * 0.01
                ),
            ],
            driveIntents: [
                TrainingDriveIntent(driveIndex: 0, value: 0.25),
            ],
            reflexCorrections: [],
            reward: rewardOffset + Double(index),
            done: false,
            truncated: index == recordCount - 1,
            episodeId: episodeID,
            policyId: "test-policy"
        )
    }
    let metadata = TrainingDatasetMetadata(
        scenarioId: "budget-test",
        seed: seed,
        timeStep: 0.01,
        determinismTier: "tier0",
        configHash: "budget-test",
        channelCount: 1,
        driveCount: 1,
        recordCount: records.count,
        episodeId: episodeID,
        policyId: "test-policy",
        rewardSum: records.reduce(0.0) { partial, record in
            partial + (record.reward ?? 0.0)
        },
        done: false,
        truncated: true,
        terminalReason: "time-limit"
    )
    return TrainingDataset(metadata: metadata, records: records)
}
