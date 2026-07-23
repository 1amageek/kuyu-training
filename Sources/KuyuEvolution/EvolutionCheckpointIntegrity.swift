import CryptoKit
import Foundation

public struct EvolutionCheckpointIntegrity: Sendable {
    public enum IntegrityError: Error, Sendable, Equatable {
        case emptyCheckpointID
        case nonFileURL(String)
        case pathOutsideArtifactRoot(path: String, root: String)
        case checkpointMissing(String)
        case checkpointIsNotDirectory(String)
        case symbolicLink(String)
        case unsupportedEntry(String)
        case emptyCheckpoint(String)
        case referenceMismatch(String)
    }

    public init() {}

    public func reference(
        checkpointID: String,
        checkpointURL: URL,
        artifactRoot: URL
    ) throws -> EvolutionCheckpointReference {
        guard !checkpointID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IntegrityError.emptyCheckpointID
        }
        let root = try standardizedFileURL(artifactRoot)
        let checkpoint = try standardizedFileURL(checkpointURL)
        try requireContained(checkpoint, in: root)

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: checkpoint.path) else {
            throw IntegrityError.checkpointMissing(checkpoint.path)
        }
        let checkpointValues = try checkpoint.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard checkpointValues.isSymbolicLink != true else {
            throw IntegrityError.symbolicLink(checkpoint.path)
        }
        guard checkpointValues.isDirectory == true else {
            throw IntegrityError.checkpointIsNotDirectory(checkpoint.path)
        }
        guard let enumerator = fileManager.enumerator(atPath: checkpoint.path) else {
            throw IntegrityError.checkpointMissing(checkpoint.path)
        }

        var files: [(relativePath: String, url: URL)] = []
        for case let relativePath as String in enumerator {
            try Task.checkCancellation()
            let entryURL = checkpoint.appendingPathComponent(relativePath, isDirectory: false)
            let values = try entryURL.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true else {
                throw IntegrityError.symbolicLink(relativePath)
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else {
                throw IntegrityError.unsupportedEntry(relativePath)
            }
            files.append((relativePath, entryURL))
        }
        guard !files.isEmpty else {
            throw IntegrityError.emptyCheckpoint(checkpoint.path)
        }
        files.sort { $0.relativePath < $1.relativePath }

        var hasher = SHA256()
        var totalByteCount = 0
        for file in files {
            try Task.checkCancellation()
            let data = try Data(contentsOf: file.url, options: [.mappedIfSafe])
            hasher.update(data: Data(file.relativePath.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: data)
            hasher.update(data: Data([0]))
            totalByteCount += data.count
            try Task.checkCancellation()
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return EvolutionCheckpointReference(
            checkpointID: checkpointID,
            checkpointURL: checkpoint,
            sha256Digest: digest,
            fileCount: files.count,
            byteCount: totalByteCount
        )
    }

    public func validate(
        _ reference: EvolutionCheckpointReference,
        expectedCheckpointID: String,
        expectedCheckpointURL: URL,
        artifactRoot: URL
    ) throws {
        let actual = try self.reference(
            checkpointID: expectedCheckpointID,
            checkpointURL: expectedCheckpointURL,
            artifactRoot: artifactRoot
        )
        guard reference == actual else {
            throw IntegrityError.referenceMismatch(expectedCheckpointID)
        }
    }

    private func standardizedFileURL(_ url: URL) throws -> URL {
        guard url.isFileURL else {
            throw IntegrityError.nonFileURL(url.absoluteString)
        }
        return url.standardizedFileURL
    }

    private func requireContained(_ url: URL, in root: URL) throws {
        let resolvedRoot = root.resolvingSymlinksInPath().path
        let resolvedPath = url.resolvingSymlinksInPath().path
        let rootPrefix = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        guard resolvedPath.hasPrefix(rootPrefix), resolvedPath != resolvedRoot else {
            throw IntegrityError.pathOutsideArtifactRoot(path: resolvedPath, root: resolvedRoot)
        }
    }
}
