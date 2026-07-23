import Foundation

public struct EvolutionCandidateArtifactRetentionStore: Sendable {
    public enum StoreError: Error, Sendable, Equatable {
        case invalidCheckpointPath(String)
        case symbolicLinkCheckpoint(String)
        case conflictingRecord(String)
        case invalidRecord(String)
        case invalidDeletion(path: String, reason: String)
        case unsupportedSchemaVersion(path: String, version: Int)
        case unsafeRetentionDirectory(String)
        case runIDMismatch(path: String, expected: String, actual: String)
    }

    public init() {}

    public func records(in artifactDirectory: URL) throws -> [EvolutionCandidateArtifactRetentionRecord] {
        let directory = try validatedRetentionDirectory(
            in: artifactDirectory,
            createIfMissing: false
        )
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        let records = try entries.map { url in
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true,
                  values.isRegularFile == true,
                  url.lastPathComponent.hasPrefix("generation-"),
                  url.pathExtension == "json" else {
                throw StoreError.invalidRecord(url.path)
            }
            let decoded = try record(at: url)
            guard url.lastPathComponent == "generation-\(decoded.generationIndex).json" else {
                throw StoreError.invalidRecord(url.path)
            }
            try validate(decoded, in: artifactDirectory)
            return decoded
        }.sorted { $0.generationIndex < $1.generationIndex }
        for (expectedGeneration, record) in records.enumerated() {
            guard record.generationIndex == expectedGeneration else {
                throw StoreError.invalidRecord(
                    "generation-chain-expected-\(expectedGeneration)-actual-\(record.generationIndex)"
                )
            }
        }
        return records
    }

    public func write(
        _ record: EvolutionCandidateArtifactRetentionRecord,
        in artifactDirectory: URL
    ) throws {
        try validate(record, in: artifactDirectory)
        _ = try validatedRetentionDirectory(
            in: artifactDirectory,
            createIfMissing: true
        )
        let url = recordURL(generationIndex: record.generationIndex, in: artifactDirectory)
        if FileManager.default.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw StoreError.invalidRecord(url.path)
            }
            guard try self.record(at: url) == record else {
                throw StoreError.conflictingRecord(url.path)
            }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: url, options: [.atomic])
    }

    public func reconcile(in artifactDirectory: URL, expectedRunID: String) throws {
        for record in try records(in: artifactDirectory) {
            guard record.runID == expectedRunID else {
                throw StoreError.runIDMismatch(
                    path: "generation-\(record.generationIndex)",
                    expected: expectedRunID,
                    actual: record.runID
                )
            }
            try deleteScheduledArtifacts(record, in: artifactDirectory)
        }
    }

    public func deleteScheduledArtifacts(
        _ record: EvolutionCandidateArtifactRetentionRecord,
        in artifactDirectory: URL
    ) throws {
        try validate(record, in: artifactDirectory)
        for deletion in record.deletions {
            let url = try checkpointURL(
                relativePath: deletion.relativePath,
                artifactDirectory: artifactDirectory,
                requiresExistingPath: false
            )
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try EvolutionCheckpointIntegrity().validate(
                    deletion.checkpointReference,
                    expectedCheckpointID: deletion.checkpointReference.checkpointID,
                    expectedCheckpointURL: url,
                    artifactRoot: artifactDirectory
                )
            } catch {
                throw StoreError.invalidDeletion(
                    path: deletion.relativePath,
                    reason: "checkpoint-reference-mismatch: \(error)"
                )
            }
            try FileManager.default.removeItem(at: url)
        }
    }

    public func relativeCheckpointPath(
        _ checkpointURL: URL,
        artifactDirectory: URL
    ) throws -> String {
        let root = resolved(artifactDirectory)
        try rejectDirectSymbolicLink(artifactDirectory)
        let candidateRootURL = artifactDirectory.appendingPathComponent("candidates", isDirectory: true)
        try rejectDirectSymbolicLink(candidateRootURL)
        let candidateRoot = resolved(candidateRootURL)
        guard isStrictDescendant(candidateRoot.path, of: root.path) else {
            throw StoreError.invalidCheckpointPath(candidateRoot.path)
        }
        if FileManager.default.fileExists(atPath: checkpointURL.path) {
            let values = try checkpointURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw StoreError.symbolicLinkCheckpoint(checkpointURL.path)
            }
        }
        let checkpoint = resolved(checkpointURL)
        guard isStrictDescendant(checkpoint.path, of: candidateRoot.path) else {
            throw StoreError.invalidCheckpointPath(checkpoint.path)
        }
        return String(checkpoint.path.dropFirst(root.path.count + 1))
    }

    public func byteCount(
        relativePath: String,
        artifactDirectory: URL
    ) throws -> Int64 {
        let url = try checkpointURL(
            relativePath: relativePath,
            artifactDirectory: artifactDirectory,
            requiresExistingPath: false
        )
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }
        if !isDirectory.boolValue {
            return try regularFileByteCount(url)
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            throw StoreError.invalidCheckpointPath(url.path)
        }
        var total: Int64 = 0
        for case let entry as URL in enumerator {
            let values = try entry.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            let bytes = Int64(values.fileSize ?? 0)
            total = total > Int64.max - bytes ? Int64.max : total + bytes
        }
        return total
    }

    private func validate(
        _ record: EvolutionCandidateArtifactRetentionRecord,
        in artifactDirectory: URL
    ) throws {
        guard record.schemaVersion == EvolutionCandidateArtifactRetentionRecord.currentSchemaVersion,
              record.generationIndex >= 0,
              !record.runID.isEmpty else {
            throw StoreError.invalidRecord("generation-\(record.generationIndex)")
        }
        var protectedPaths = Set<String>()
        for path in record.protectedCheckpointPaths {
            guard protectedPaths.insert(path).inserted else {
                throw StoreError.invalidRecord(path)
            }
            _ = try checkpointURL(
                relativePath: path,
                artifactDirectory: artifactDirectory,
                requiresExistingPath: false
            )
        }
        var deletionPaths = Set<String>()
        for deletion in record.deletions {
            guard !deletion.candidateID.isEmpty,
                  deletion.generationIndex >= 0,
                  deletion.generationIndex <= record.generationIndex else {
                throw StoreError.invalidDeletion(
                    path: deletion.relativePath,
                    reason: "candidate-identity"
                )
            }
            guard !deletion.reason.isEmpty else {
                throw StoreError.invalidDeletion(path: deletion.relativePath, reason: "reason")
            }
            guard deletion.checkpointReference.byteCount >= 0,
                  deletion.checkpointReference.fileCount > 0,
                  !deletion.checkpointReference.sha256Digest.isEmpty else {
                throw StoreError.invalidDeletion(
                    path: deletion.relativePath,
                    reason: "checkpoint-reference"
                )
            }
            guard !protectedPaths.contains(deletion.relativePath) else {
                throw StoreError.invalidDeletion(
                    path: deletion.relativePath,
                    reason: "protected-path"
                )
            }
            guard deletionPaths.insert(deletion.relativePath).inserted else {
                throw StoreError.invalidDeletion(
                    path: deletion.relativePath,
                    reason: "duplicate-path"
                )
            }
            let url = try checkpointURL(
                relativePath: deletion.relativePath,
                artifactDirectory: artifactDirectory,
                requiresExistingPath: false
            )
            guard resolved(deletion.checkpointReference.checkpointURL).path ==
                    resolved(url).path else {
                throw StoreError.invalidDeletion(
                    path: deletion.relativePath,
                    reason: "checkpoint-url"
                )
            }
        }
    }

    private func checkpointURL(
        relativePath: String,
        artifactDirectory: URL,
        requiresExistingPath: Bool
    ) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              relativePath.split(separator: "/").first == "candidates",
              !relativePath.split(separator: "/").contains("..") else {
            throw StoreError.invalidCheckpointPath(relativePath)
        }
        let root = resolved(artifactDirectory)
        try rejectDirectSymbolicLink(artifactDirectory)
        let candidateRootURL = artifactDirectory.appendingPathComponent("candidates", isDirectory: true)
        try rejectDirectSymbolicLink(candidateRootURL)
        let candidateRoot = resolved(candidateRootURL)
        guard isStrictDescendant(candidateRoot.path, of: root.path) else {
            throw StoreError.invalidCheckpointPath(candidateRoot.path)
        }
        let url = artifactDirectory.appendingPathComponent(relativePath).standardizedFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw StoreError.symbolicLinkCheckpoint(url.path)
            }
            guard isStrictDescendant(resolved(url).path, of: candidateRoot.path) else {
                throw StoreError.invalidCheckpointPath(url.path)
            }
        } else if requiresExistingPath {
            throw StoreError.invalidCheckpointPath(url.path)
        }
        return url
    }

    private func record(at url: URL) throws -> EvolutionCandidateArtifactRetentionRecord {
        let record = try JSONDecoder().decode(
            EvolutionCandidateArtifactRetentionRecord.self,
            from: Data(contentsOf: url)
        )
        guard record.schemaVersion == EvolutionCandidateArtifactRetentionRecord.currentSchemaVersion else {
            throw StoreError.unsupportedSchemaVersion(path: url.path, version: record.schemaVersion)
        }
        return record
    }

    private func recordURL(generationIndex: Int, in artifactDirectory: URL) -> URL {
        retentionDirectory(in: artifactDirectory)
            .appendingPathComponent("generation-\(generationIndex).json", isDirectory: false)
    }

    private func retentionDirectory(in artifactDirectory: URL) -> URL {
        artifactDirectory
            .appendingPathComponent("retention", isDirectory: true)
            .appendingPathComponent("candidate-checkpoints", isDirectory: true)
    }

    private func validatedRetentionDirectory(
        in artifactDirectory: URL,
        createIfMissing: Bool
    ) throws -> URL {
        try rejectDirectSymbolicLink(artifactDirectory)
        let resolvedRoot = resolved(artifactDirectory)
        let retentionRoot = artifactDirectory.appendingPathComponent("retention", isDirectory: true)
        let directory = retentionDirectory(in: artifactDirectory)
        for candidate in [retentionRoot, directory] {
            try rejectDirectSymbolicLink(candidate)
            if FileManager.default.fileExists(atPath: candidate.path) {
                guard isStrictDescendant(resolved(candidate).path, of: resolvedRoot.path) else {
                    throw StoreError.unsafeRetentionDirectory(candidate.path)
                }
            }
        }
        if createIfMissing {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try rejectDirectSymbolicLink(retentionRoot)
            try rejectDirectSymbolicLink(directory)
            guard isStrictDescendant(resolved(directory).path, of: resolvedRoot.path) else {
                throw StoreError.unsafeRetentionDirectory(directory.path)
            }
        }
        return directory
    }

    private func rejectDirectSymbolicLink(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw StoreError.unsafeRetentionDirectory(url.path)
        }
    }

    private func regularFileByteCount(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isSymbolicLink != true, values.isRegularFile == true else { return 0 }
        return Int64(values.fileSize ?? 0)
    }

    private func resolved(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func isStrictDescendant(_ path: String, of root: String) -> Bool {
        path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
