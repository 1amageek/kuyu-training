import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public struct TrainingDatasetMixManifest: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let createdAt: Date
    public let sources: [TrainingDatasetMixSource]
    public let datasetCount: Int
    public let totalRecordCount: Int

    public init(
        schemaVersion: Int = TrainingDatasetMixManifest.currentSchemaVersion,
        createdAt: Date,
        sources: [TrainingDatasetMixSource],
        datasetCount: Int,
        totalRecordCount: Int
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.sources = sources
        self.datasetCount = datasetCount
        self.totalRecordCount = totalRecordCount
    }
}

public struct TrainingDatasetMixSource: Sendable, Codable, Equatable {
    public let index: Int
    public let path: String
    public let copiedDatasetCount: Int
    public let copiedRecordCount: Int

    public init(index: Int, path: String, copiedDatasetCount: Int, copiedRecordCount: Int) {
        self.index = index
        self.path = path
        self.copiedDatasetCount = copiedDatasetCount
        self.copiedRecordCount = copiedRecordCount
    }
}

public struct TrainingDatasetMixer: Sendable {
    public enum MixError: Error, Equatable {
        case noSources
        case noDatasetsFound([String])
        case destinationAlreadyExists(String)
        case datasetContractViolation(path: String, reason: TrainingDatasetContractValidator.ValidationError)
    }

    public init() {}

    @discardableResult
    public func mix(
        sources: [URL],
        to outputDirectory: URL,
        createdAt: Date = Date(),
        datasetContract: TrainingDatasetContract? = TrainingDatasetContract()
    ) throws -> TrainingDatasetMixManifest {
        guard !sources.isEmpty else {
            throw MixError.noSources
        }

        let discovered = try sources.enumerated().map { index, source in
            let datasets = try discoverDatasets(in: source)
            return SourceDatasets(index: index, source: source, datasets: datasets)
        }
        let datasetCount = discovered.reduce(0) { $0 + $1.datasets.count }
        guard datasetCount > 0 else {
            throw MixError.noDatasetsFound(sources.map(\.path))
        }

        let enforcedDatasetContract = datasetContract ?? TrainingDatasetContract()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var manifestSources: [TrainingDatasetMixSource] = []
        var totalRecordCount = 0
        for source in discovered {
            var copiedRecordCount = 0
            for dataset in source.datasets {
                let destination = outputDirectory.appendingPathComponent(
                    destinationName(sourceIndex: source.index, source: source.source, dataset: dataset),
                    isDirectory: true
                )
                guard !fileManager.fileExists(atPath: destination.path) else {
                    throw MixError.destinationAlreadyExists(destination.path)
                }
                let loaded: TrainingDataset
                do {
                    loaded = try TrainingDatasetContractValidator().loadAndValidate(
                        from: dataset,
                        against: enforcedDatasetContract
                    )
                } catch let error as TrainingDatasetContractValidator.ValidationError {
                    throw MixError.datasetContractViolation(path: dataset.path, reason: error)
                }
                try fileManager.copyItem(at: dataset, to: destination)
                copiedRecordCount += loaded.metadata.recordCount
            }
            totalRecordCount += copiedRecordCount
            manifestSources.append(
                TrainingDatasetMixSource(
                    index: source.index,
                    path: source.source.path,
                    copiedDatasetCount: source.datasets.count,
                    copiedRecordCount: copiedRecordCount
                )
            )
        }

        let manifest = TrainingDatasetMixManifest(
            createdAt: createdAt,
            sources: manifestSources,
            datasetCount: datasetCount,
            totalRecordCount: totalRecordCount
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(
            to: outputDirectory.appendingPathComponent("dataset-mix-manifest.json"),
            options: [.atomic]
        )
        return manifest
    }

    private func discoverDatasets(in source: URL) throws -> [URL] {
        if isDatasetDirectory(source) {
            return [source]
        }
        let fileManager = FileManager.default
        let children = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let directories = try children.filter { child in
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            return values.isDirectory == true
        }
        return directories
            .filter { isDatasetDirectory($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func isDatasetDirectory(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: directory.appendingPathComponent("meta.json").path)
            && fileManager.fileExists(atPath: directory.appendingPathComponent("records.jsonl").path)
    }

    private func destinationName(sourceIndex: Int, source: URL, dataset: URL) -> String {
        let sourceName = sanitized(source.lastPathComponent.isEmpty ? "source" : source.lastPathComponent)
        let datasetName = sanitized(dataset.lastPathComponent.isEmpty ? "dataset" : dataset.lastPathComponent)
        return String(format: "source_%03d_%@_%@", sourceIndex + 1, sourceName, datasetName)
    }

    private func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let result = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }.joined()
        return result.isEmpty ? "dataset" : result
    }

    private struct SourceDatasets {
        let index: Int
        let source: URL
        let datasets: [URL]
    }
}
