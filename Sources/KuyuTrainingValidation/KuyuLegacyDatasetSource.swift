import CryptoKit
import Foundation

public struct KuyuLegacyDatasetSource: Sendable, Equatable {
    public enum LoadError: Error, Sendable, Equatable {
        case artifactTooLarge(URL)
        case unsupportedSchemaVersion(Int)
    }

    public let dataset: TrainingDataset
    public let sourceDigest: String

    private init(dataset: TrainingDataset, sourceDigest: String) {
        self.dataset = dataset
        self.sourceDigest = sourceDigest
    }

    public static func load(from directory: URL) throws -> KuyuLegacyDatasetSource {
        let digest = try digest(of: directory)
        // Legacy migration must inspect missing terminal facts and return a
        // typed rejection report. Terminal semantics are therefore validated
        // by the migrator, not consumed by this structural source loader.
        let dataset = try TrainingDatasetContractValidator().validatedDataset(
            in: directory,
            against: TrainingDatasetContract(
                requiresTerminalFacts: false,
                allowedSchemaVersions: Set(3...6)
            )
        )
        guard (3...6).contains(dataset.metadata.schemaVersion) else {
            throw LoadError.unsupportedSchemaVersion(dataset.metadata.schemaVersion)
        }
        return KuyuLegacyDatasetSource(dataset: dataset, sourceDigest: digest)
    }

    private static func digest(of directory: URL) throws -> String {
        try KuyuDatasetPOSIX.withDirectory(at: directory) { directoryDescriptor in
            var hasher = SHA256()
            try digestFile(
                directoryDescriptor: directoryDescriptor,
                directoryURL: directory,
                name: "meta.json",
                hasher: &hasher
            )
            hasher.update(data: Data([0x0A]))
            try digestFile(
                directoryDescriptor: directoryDescriptor,
                directoryURL: directory,
                name: "records.jsonl",
                hasher: &hasher
            )
            return KuyuDatasetDigest.hex(hasher.finalize())
        }
    }

    private static func digestFile(
        directoryDescriptor: Int32,
        directoryURL: URL,
        name: String,
        hasher: inout SHA256
    ) throws {
        let url = directoryURL.appendingPathComponent(name, isDirectory: false)
        try KuyuDatasetPOSIX.withRegularFile(
            in: directoryDescriptor,
            name: name,
            path: url
        ) { descriptor in
            let size = try KuyuDatasetPOSIX.regularFileSize(descriptor, path: url)
            guard size <= KuyuDatasetReader.defaultMaximumRecordsBytes else {
                throw LoadError.artifactTooLarge(url)
            }
            var buffer = [UInt8](repeating: 0, count: KuyuDatasetReader.defaultChunkSize)
            while true {
                let count = try KuyuDatasetPOSIX.read(descriptor, into: &buffer, path: url)
                if count == 0 { break }
                hasher.update(data: Data(buffer[0..<count]))
            }
        }
    }
}
