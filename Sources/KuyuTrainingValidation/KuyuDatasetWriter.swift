import CryptoKit
import Foundation
import KuyuTrainingContracts

public struct KuyuDatasetWriter: Sendable {
    private let validator: KuyuDatasetValidator
    private let reader: KuyuDatasetReader

    public init(validator: KuyuDatasetValidator = KuyuDatasetValidator()) {
        self.validator = validator
        self.reader = KuyuDatasetReader(validator: validator)
    }

    @discardableResult
    public func write<Records: Sequence>(
        descriptor: KuyuDatasetDescriptor,
        records: Records,
        to destination: URL
    ) throws -> KuyuDatasetManifest where Records.Element == KuyuDatasetRecord {
        try validator.validateDescriptor(descriptor)
        let parent = destination.deletingLastPathComponent()
        let destinationName = destination.lastPathComponent
        guard !destinationName.isEmpty, destinationName != ".", destinationName != ".." else {
            throw KuyuDatasetArtifactError.invalidDestinationParent(parent)
        }

        return try KuyuDatasetPOSIX.withDirectory(at: parent) { parentDescriptor in
            guard try !KuyuDatasetPOSIX.entryExists(
                in: parentDescriptor,
                name: destinationName,
                path: destination
            ) else {
                throw KuyuDatasetArtifactError.destinationExists(destination)
            }

            let stagingName = ".kuyu-dataset.staging.\(UUID().uuidString)"
            let staging = parent.appendingPathComponent(stagingName, isDirectory: true)
            try KuyuDatasetPOSIX.makeDirectory(
                in: parentDescriptor,
                name: stagingName,
                path: staging
            )

            var published = false
            do {
                let manifest = try KuyuDatasetPOSIX.withDirectory(
                    in: parentDescriptor,
                    name: stagingName,
                    path: staging
                ) { stagingDescriptor in
                    let recordsURL = staging.appendingPathComponent("records.jsonl", isDirectory: false)
                    let result = try writeRecords(
                        descriptor: descriptor,
                        records: records,
                        directoryDescriptor: stagingDescriptor,
                        url: recordsURL
                    )
                    let manifest = KuyuDatasetManifest(
                        descriptor: descriptor,
                        recordCount: result.count,
                        recordsDigest: result.digest
                    )
                    let manifestURL = staging.appendingPathComponent("manifest.json", isDirectory: false)
                    try writeManifest(
                        manifest,
                        directoryDescriptor: stagingDescriptor,
                        url: manifestURL
                    )
                    _ = try reader.validate(
                        directoryDescriptor: stagingDescriptor,
                        directoryURL: staging
                    )
                    try KuyuDatasetDurability.synchronize(
                        stagingDescriptor,
                        path: staging,
                        operation: "fsync staged directory"
                    )

                    let descriptorIdentity = try KuyuDatasetPOSIX.identity(
                        of: stagingDescriptor,
                        path: staging
                    )
                    let entryIdentity = try KuyuDatasetPOSIX.identity(
                        in: parentDescriptor,
                        name: stagingName,
                        path: staging
                    )
                    guard descriptorIdentity == entryIdentity else {
                        throw KuyuDatasetArtifactError.publicationFailed(
                            source: staging,
                            destination: destination,
                            reason: "staging directory identity changed"
                        )
                    }

                    try KuyuDatasetPOSIX.publishDirectory(
                        parentDescriptor: parentDescriptor,
                        stagingName: stagingName,
                        stagingPath: staging,
                        destinationName: destinationName,
                        destinationPath: destination
                    )
                    published = true
                    do {
                        try KuyuDatasetDurability.synchronize(
                            parentDescriptor,
                            path: parent,
                            operation: "fsync publication parent"
                        )
                    } catch KuyuDatasetArtifactError.synchronizationFailed(_, _, let code) {
                        throw KuyuDatasetArtifactError.publishedButDurabilityUncertain(
                            destination: destination,
                            code: code
                        )
                    }
                    return manifest
                }
                return manifest
            } catch {
                let primary = error
                guard !published else { throw primary }
                do {
                    try cleanupStaging(
                        parentDescriptor: parentDescriptor,
                        parentURL: parent,
                        stagingName: stagingName,
                        stagingURL: staging
                    )
                } catch {
                    throw KuyuDatasetArtifactError.operationAndCleanupFailed(
                        operation: String(describing: primary),
                        cleanup: String(describing: error)
                    )
                }
                throw primary
            }
        }
    }

    private func writeRecords<Records: Sequence>(
        descriptor: KuyuDatasetDescriptor,
        records: Records,
        directoryDescriptor: Int32,
        url: URL
    ) throws -> (count: UInt64, digest: String) where Records.Element == KuyuDatasetRecord {
        try KuyuDatasetPOSIX.withCreatedFile(
            in: directoryDescriptor,
            name: "records.jsonl",
            path: url
        ) { descriptorValue in
            let provisionalManifest = KuyuDatasetManifest(
                descriptor: descriptor,
                recordCount: 0,
                recordsDigest: KuyuDatasetDigest.zero
            )
            var validationSession = try validator.validationSession(for: provisionalManifest)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let newline = Data([0x0A])
            var hasher = SHA256()
            var count: UInt64 = 0

            for record in records {
                try validationSession.consume(record)
                let data: Data
                do {
                    data = try encoder.encode(record)
                } catch {
                    throw KuyuDatasetArtifactError.writeFailed(
                        path: url,
                        operation: "encode record \(count)",
                        reason: String(describing: error)
                    )
                }
                guard data.count <= KuyuDatasetReader.defaultMaximumRecordBytes else {
                    throw KuyuDatasetArtifactError.recordTooLarge(
                        index: count,
                        maximumBytes: KuyuDatasetReader.defaultMaximumRecordBytes
                    )
                }
                try KuyuDatasetPOSIX.write(
                    data,
                    to: descriptorValue,
                    path: url,
                    operation: "write record \(count)"
                )
                try KuyuDatasetPOSIX.write(
                    newline,
                    to: descriptorValue,
                    path: url,
                    operation: "write record delimiter \(count)"
                )
                hasher.update(data: data)
                hasher.update(data: newline)
                count += 1
            }
            guard count > 0 else {
                throw KuyuDatasetValidator.ValidationError.emptyDataset
            }
            try KuyuDatasetDurability.synchronize(
                descriptorValue,
                path: url,
                operation: "fsync records"
            )
            return (count, KuyuDatasetDigest.hex(hasher.finalize()))
        }
    }

    private func writeManifest(
        _ manifest: KuyuDatasetManifest,
        directoryDescriptor: Int32,
        url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(manifest)
        } catch {
            throw KuyuDatasetArtifactError.writeFailed(
                path: url,
                operation: "encode manifest",
                reason: String(describing: error)
            )
        }
        guard data.count <= KuyuDatasetReader.defaultMaximumManifestBytes else {
            throw KuyuDatasetArtifactError.manifestTooLarge(
                path: url,
                maximumBytes: KuyuDatasetReader.defaultMaximumManifestBytes,
                actualBytes: data.count
            )
        }
        try KuyuDatasetPOSIX.withCreatedFile(
            in: directoryDescriptor,
            name: "manifest.json",
            path: url
        ) { descriptor in
            try KuyuDatasetPOSIX.write(
                data,
                to: descriptor,
                path: url,
                operation: "write manifest"
            )
            try KuyuDatasetDurability.synchronize(
                descriptor,
                path: url,
                operation: "fsync manifest"
            )
        }
    }

    private func cleanupStaging(
        parentDescriptor: Int32,
        parentURL: URL,
        stagingName: String,
        stagingURL: URL
    ) throws {
        if try KuyuDatasetPOSIX.entryExists(
            in: parentDescriptor,
            name: stagingName,
            path: stagingURL
        ) {
            try KuyuDatasetPOSIX.withDirectory(
                in: parentDescriptor,
                name: stagingName,
                path: stagingURL
            ) { stagingDescriptor in
                try KuyuDatasetPOSIX.removeFileIfPresent(
                    in: stagingDescriptor,
                    name: "records.jsonl",
                    path: stagingURL.appendingPathComponent("records.jsonl")
                )
                try KuyuDatasetPOSIX.removeFileIfPresent(
                    in: stagingDescriptor,
                    name: "manifest.json",
                    path: stagingURL.appendingPathComponent("manifest.json")
                )
                try KuyuDatasetDurability.synchronize(
                    stagingDescriptor,
                    path: stagingURL,
                    operation: "fsync staging cleanup"
                )
            }
            try KuyuDatasetPOSIX.removeDirectoryIfPresent(
                in: parentDescriptor,
                name: stagingName,
                path: stagingURL
            )
            try KuyuDatasetDurability.synchronize(
                parentDescriptor,
                path: parentURL,
                operation: "fsync cleanup parent"
            )
        }
    }
}
