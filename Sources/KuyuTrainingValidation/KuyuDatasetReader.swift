import CryptoKit
import Foundation
import KuyuTrainingContracts

public struct KuyuDatasetReader: Sendable {
    public static let defaultMaximumManifestBytes = 1 * 1_024 * 1_024
    public static let defaultMaximumRecordBytes = 4 * 1_024 * 1_024
    public static let defaultMaximumRecordsBytes: Int64 = 64 * 1_024 * 1_024 * 1_024
    public static let defaultChunkSize = 64 * 1_024

    private static let maximumAllowedManifestBytes = 16 * 1_024 * 1_024
    private static let maximumAllowedRecordBytes = 256 * 1_024 * 1_024
    private static let maximumAllowedRecordsBytes: Int64 = 1_024 * 1_024 * 1_024 * 1_024
    private static let maximumAllowedChunkSize = 16 * 1_024 * 1_024

    private let maximumManifestBytes: Int
    private let maximumRecordBytes: Int
    private let maximumRecordsBytes: Int64
    private let chunkSize: Int
    private let validator: KuyuDatasetValidator

    public init(validator: KuyuDatasetValidator = KuyuDatasetValidator()) {
        self.maximumManifestBytes = Self.defaultMaximumManifestBytes
        self.maximumRecordBytes = Self.defaultMaximumRecordBytes
        self.maximumRecordsBytes = Self.defaultMaximumRecordsBytes
        self.chunkSize = Self.defaultChunkSize
        self.validator = validator
    }

    public init(
        maximumManifestBytes: Int,
        maximumRecordBytes: Int,
        maximumRecordsBytes: Int64 = KuyuDatasetReader.defaultMaximumRecordsBytes,
        chunkSize: Int,
        validator: KuyuDatasetValidator = KuyuDatasetValidator()
    ) throws {
        try Self.validateConfiguration(
            maximumManifestBytes: maximumManifestBytes,
            maximumRecordBytes: maximumRecordBytes,
            maximumRecordsBytes: maximumRecordsBytes,
            chunkSize: chunkSize
        )
        self.maximumManifestBytes = maximumManifestBytes
        self.maximumRecordBytes = maximumRecordBytes
        self.maximumRecordsBytes = maximumRecordsBytes
        self.chunkSize = chunkSize
        self.validator = validator
    }

    public func manifest(in directory: URL) throws -> KuyuDatasetManifest {
        try KuyuDatasetPOSIX.withDirectory(at: directory) { directoryDescriptor in
            try loadedManifest(
                directoryDescriptor: directoryDescriptor,
                directoryURL: directory
            ).manifest
        }
    }

    @discardableResult
    public func validate(_ directory: URL) throws -> KuyuDatasetReadSummary {
        try KuyuDatasetPOSIX.withDirectory(at: directory) { directoryDescriptor in
            try validate(directoryDescriptor: directoryDescriptor, directoryURL: directory)
        }
    }

    /// Streams records through structural and digest validation without creating a private snapshot.
    /// Consumers must defer externally visible effects until this method returns successfully.
    @discardableResult
    public func inspect(
        _ directory: URL,
        consume: @escaping (KuyuDatasetRecord) throws -> Void
    ) throws -> KuyuDatasetReadSummary {
        try KuyuDatasetPOSIX.withDirectory(at: directory) { directoryDescriptor in
            let loadedManifest = try loadedManifest(
                directoryDescriptor: directoryDescriptor,
                directoryURL: directory
            )
            let recordsURL = directory.appendingPathComponent("records.jsonl", isDirectory: false)
            return try KuyuDatasetPOSIX.withRegularFile(
                in: directoryDescriptor,
                name: "records.jsonl",
                path: recordsURL
            ) { recordsDescriptor in
                let size = try KuyuDatasetPOSIX.regularFileSize(
                    recordsDescriptor,
                    path: recordsURL
                )
                try validateRecordsSize(size, path: recordsURL)
                return try scan(
                    descriptor: recordsDescriptor,
                    recordsURL: recordsURL,
                    loadedManifest: loadedManifest,
                    consume: consume
                )
            }
        }
    }

    @discardableResult
    public func read(
        _ directory: URL,
        consume: @escaping (KuyuDatasetRecord) throws -> Void
    ) throws -> KuyuDatasetReadSummary {
        try KuyuDatasetPOSIX.withDirectory(at: directory) { directoryDescriptor in
            let loadedManifest = try loadedManifest(
                directoryDescriptor: directoryDescriptor,
                directoryURL: directory
            )
            let recordsURL = directory.appendingPathComponent("records.jsonl", isDirectory: false)
            return try KuyuDatasetPOSIX.withRegularFile(
                in: directoryDescriptor,
                name: "records.jsonl",
                path: recordsURL
            ) { sourceDescriptor in
                let sourceSize = try KuyuDatasetPOSIX.regularFileSize(sourceDescriptor, path: recordsURL)
                try validateRecordsSize(sourceSize, path: recordsURL)
                return try KuyuDatasetPOSIX.withUnlinkedTemporaryFile { snapshotDescriptor, snapshotURL in
                    _ = try KuyuDatasetPOSIX.copy(
                        from: sourceDescriptor,
                        sourcePath: recordsURL,
                        to: snapshotDescriptor,
                        destinationPath: snapshotURL,
                        chunkSize: chunkSize,
                        maximumBytes: maximumRecordsBytes
                    )
                    let validated = try scan(
                        descriptor: snapshotDescriptor,
                        recordsURL: snapshotURL,
                        loadedManifest: loadedManifest,
                        consume: nil
                    )
                    try KuyuDatasetPOSIX.rewind(snapshotDescriptor, path: snapshotURL)
                    let consumed = try scan(
                        descriptor: snapshotDescriptor,
                        recordsURL: snapshotURL,
                        loadedManifest: loadedManifest,
                        consume: consume
                    )
                    guard consumed == validated else {
                        throw KuyuDatasetArtifactError.manifestChangedDuringRead
                    }
                    return consumed
                }
            }
        }
    }

    func validate(
        directoryDescriptor: Int32,
        directoryURL: URL
    ) throws -> KuyuDatasetReadSummary {
        let loadedManifest = try loadedManifest(
            directoryDescriptor: directoryDescriptor,
            directoryURL: directoryURL
        )
        let recordsURL = directoryURL.appendingPathComponent("records.jsonl", isDirectory: false)
        return try KuyuDatasetPOSIX.withRegularFile(
            in: directoryDescriptor,
            name: "records.jsonl",
            path: recordsURL
        ) { recordsDescriptor in
            let size = try KuyuDatasetPOSIX.regularFileSize(recordsDescriptor, path: recordsURL)
            try validateRecordsSize(size, path: recordsURL)
            return try scan(
                descriptor: recordsDescriptor,
                recordsURL: recordsURL,
                loadedManifest: loadedManifest,
                consume: nil
            )
        }
    }

    private struct LoadedManifest {
        let manifest: KuyuDatasetManifest
        let digest: String
    }

    private func loadedManifest(
        directoryDescriptor: Int32,
        directoryURL: URL
    ) throws -> LoadedManifest {
        let manifestURL = directoryURL.appendingPathComponent("manifest.json", isDirectory: false)
        let loadedManifest = try KuyuDatasetPOSIX.withRegularFile(
            in: directoryDescriptor,
            name: "manifest.json",
            path: manifestURL
        ) { manifestDescriptor in
            let size = try KuyuDatasetPOSIX.regularFileSize(manifestDescriptor, path: manifestURL)
            guard size <= Int64(maximumManifestBytes) else {
                throw KuyuDatasetArtifactError.manifestTooLarge(
                    path: manifestURL,
                    maximumBytes: maximumManifestBytes,
                    actualBytes: size > Int64(Int.max) ? Int.max : Int(size)
                )
            }
            let data = try boundedData(
                descriptor: manifestDescriptor,
                path: manifestURL,
                maximumBytes: maximumManifestBytes
            )
            do {
                return LoadedManifest(
                    manifest: try JSONDecoder().decode(KuyuDatasetManifest.self, from: data),
                    digest: KuyuDatasetDigest.hex(SHA256.hash(data: data))
                )
            } catch {
                throw KuyuDatasetArtifactError.manifestDecodeFailed(
                    path: manifestURL,
                    reason: String(describing: error)
                )
            }
        }
        try validator.validate(manifest: loadedManifest.manifest)
        return loadedManifest
    }

    private func boundedData(
        descriptor: Int32,
        path: URL,
        maximumBytes: Int
    ) throws -> Data {
        try KuyuDatasetPOSIX.rewind(descriptor, path: path)
        var data = Data()
        data.reserveCapacity(min(maximumBytes, chunkSize))
        var buffer = [UInt8](repeating: 0, count: min(chunkSize, maximumBytes))
        while true {
            let count = try KuyuDatasetPOSIX.read(descriptor, into: &buffer, path: path)
            if count == 0 { return data }
            guard data.count <= maximumBytes - count else {
                throw KuyuDatasetArtifactError.manifestTooLarge(
                    path: path,
                    maximumBytes: maximumBytes,
                    actualBytes: data.count + count
                )
            }
            data.append(contentsOf: buffer[0..<count])
        }
    }

    private func scan(
        descriptor: Int32,
        recordsURL: URL,
        loadedManifest: LoadedManifest,
        consume: ((KuyuDatasetRecord) throws -> Void)?
    ) throws -> KuyuDatasetReadSummary {
        let manifest = loadedManifest.manifest
        try KuyuDatasetPOSIX.rewind(descriptor, path: recordsURL)
        var validationSession = try validator.validationSession(for: manifest)
        var hasher = SHA256()
        var line = Data()
        line.reserveCapacity(min(maximumRecordBytes, chunkSize))
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        var recordIndex: UInt64 = 0
        var finalByteWasNewline = false
        let decoder = JSONDecoder()

        while true {
            let readCount = try KuyuDatasetPOSIX.read(descriptor, into: &buffer, path: recordsURL)
            if readCount == 0 { break }
            let chunk = Data(buffer[0..<readCount])
            hasher.update(data: chunk)
            for byte in buffer[0..<readCount] {
                finalByteWasNewline = byte == 0x0A
                if finalByteWasNewline {
                    guard !line.isEmpty else {
                        throw KuyuDatasetArtifactError.emptyRecordLine(index: recordIndex)
                    }
                    let record: KuyuDatasetRecord
                    do {
                        record = try decoder.decode(KuyuDatasetRecord.self, from: line)
                    } catch {
                        throw KuyuDatasetArtifactError.recordDecodeFailed(
                            index: recordIndex,
                            reason: String(describing: error)
                        )
                    }
                    try validationSession.consume(record)
                    try consume?(record)
                    recordIndex += 1
                    line.removeAll(keepingCapacity: true)
                } else {
                    line.append(byte)
                    guard line.count <= maximumRecordBytes else {
                        throw KuyuDatasetArtifactError.recordTooLarge(
                            index: recordIndex,
                            maximumBytes: maximumRecordBytes
                        )
                    }
                }
            }
        }

        if !line.isEmpty || (recordIndex > 0 && !finalByteWasNewline) {
            throw KuyuDatasetArtifactError.missingFinalNewline
        }
        try validationSession.finish()
        let digest = KuyuDatasetDigest.hex(hasher.finalize())
        guard digest == manifest.recordsDigest else {
            throw KuyuDatasetArtifactError.recordsDigestMismatch(
                expected: manifest.recordsDigest,
                actual: digest
            )
        }
        return KuyuDatasetReadSummary(
            manifest: manifest,
            observedManifestDigest: loadedManifest.digest,
            observedRecordCount: recordIndex,
            observedRecordsDigest: digest
        )
    }

    private func validateRecordsSize(_ size: Int64, path: URL) throws {
        guard size <= maximumRecordsBytes else {
            throw KuyuDatasetArtifactError.recordsTooLarge(
                path: path,
                maximumBytes: maximumRecordsBytes,
                actualBytes: size
            )
        }
    }

    private static func validateConfiguration(
        maximumManifestBytes: Int,
        maximumRecordBytes: Int,
        maximumRecordsBytes: Int64,
        chunkSize: Int
    ) throws {
        let values = [
            ("maximumManifestBytes", maximumManifestBytes, maximumAllowedManifestBytes),
            ("maximumRecordBytes", maximumRecordBytes, maximumAllowedRecordBytes),
            ("chunkSize", chunkSize, maximumAllowedChunkSize),
        ]
        for (field, value, maximum) in values where value <= 0 || value > maximum {
            throw KuyuDatasetArtifactError.invalidConfiguration(field: field, value: value)
        }
        guard maximumRecordsBytes > 0,
              maximumRecordsBytes <= maximumAllowedRecordsBytes else {
            let value = maximumRecordsBytes > Int64(Int.max) ? Int.max : Int(maximumRecordsBytes)
            throw KuyuDatasetArtifactError.invalidConfiguration(
                field: "maximumRecordsBytes",
                value: value
            )
        }
        guard chunkSize <= maximumRecordBytes else {
            throw KuyuDatasetArtifactError.invalidConfiguration(field: "chunkSize", value: chunkSize)
        }
    }
}
