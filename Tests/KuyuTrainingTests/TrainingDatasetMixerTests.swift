import Foundation
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
}

private func temporaryDirectory(_ prefix: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
}

private func writeDataset(
    to directory: URL,
    scenarioID: String,
    seed: UInt64,
    recordCount: Int
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
        recordCount: recordCount
    )
    let records = (0..<recordCount).map { index in
        TrainingDatasetRecord(
            time: Double(index) * 0.01,
            sensors: [TrainingSensorSample(channelIndex: 0, value: Double(index), timestamp: Double(index) * 0.01)],
            driveIntents: [TrainingDriveIntent(driveIndex: 0, value: 0.5)],
            reflexCorrections: []
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
