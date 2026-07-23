import Foundation
import KuyuTrainingContracts

public struct ModelBundlePublicationStore: Sendable {
    public enum PublicationError: Error, Sendable, Equatable, LocalizedError {
        case nonFileURL(role: String, url: String)
        case pathOutsideArtifactRoot(role: String, path: String, root: String)
        case sourceMissing(String)
        case sourceIsNotDirectory(String)
        case sourceIsSymbolicLink(String)
        case destinationMatchesSource(String)
        case invalidExpectedSourceDigest(String)
        case sourceDigestMismatch(expected: String, actual: String)
        case copiedDigestMismatch(expected: String, actual: String)
        case checkpointIntegrityFailed(path: String, reason: String)
        case bundleValidationFailed(path: String, reason: String)
        case emptyRunID
        case emptyCandidateID
        case destinationDigestMismatch(expected: String, actual: String)
        case rollbackFailed(primary: String, rollback: String)
        case cleanupFailed(path: String, reason: String)

        public var errorDescription: String? {
            switch self {
            case .nonFileURL(let role, let url):
                return "\(role) must be a file URL: \(url)"
            case .pathOutsideArtifactRoot(let role, let path, let root):
                return "\(role) path is outside artifact root: \(path) is not under \(root)"
            case .sourceMissing(let path):
                return "Checkpoint source is missing: \(path)"
            case .sourceIsNotDirectory(let path):
                return "Checkpoint source must be a directory: \(path)"
            case .sourceIsSymbolicLink(let path):
                return "Checkpoint source must not be a symbolic link: \(path)"
            case .destinationMatchesSource(let path):
                return "Checkpoint destination must differ from source: \(path)"
            case .invalidExpectedSourceDigest(let digest):
                return "Expected checkpoint digest must be lowercase SHA-256: \(digest)"
            case .sourceDigestMismatch(let expected, let actual):
                return "Checkpoint source digest mismatch: expected \(expected), actual \(actual)"
            case .copiedDigestMismatch(let expected, let actual):
                return "Published checkpoint digest mismatch: expected \(expected), actual \(actual)"
            case .checkpointIntegrityFailed(let path, let reason):
                return "Checkpoint integrity validation failed at \(path): \(reason)"
            case .bundleValidationFailed(let path, let reason):
                return "Checkpoint bundle validation failed at \(path): \(reason)"
            case .emptyRunID:
                return "Checkpoint publication run ID must not be empty."
            case .emptyCandidateID:
                return "Checkpoint publication candidate ID must not be empty."
            case .destinationDigestMismatch(let expected, let actual):
                return "Checkpoint destination digest mismatch: expected \(expected), actual \(actual)"
            case .rollbackFailed(let primary, let rollback):
                return "Checkpoint publication failed and rollback failed: primary=\(primary), rollback=\(rollback)"
            case .cleanupFailed(let path, let reason):
                return "Checkpoint publication cleanup failed at \(path): \(reason)"
            }
        }
    }

    private let validator: any ModelBundlePublicationValidating

    public init(validator: any ModelBundlePublicationValidating) {
        self.validator = validator
    }

    public func publish(source: URL, request: CheckpointPublicationRequest) throws -> CheckpointPublicationReceipt {
        guard !request.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PublicationError.emptyRunID
        }
        guard !request.candidateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PublicationError.emptyCandidateID
        }
        let artifactRoot = try standardizedFileURL(request.artifactRoot, role: "artifactRoot")
        let sourceURL = try standardizedFileURL(source, role: "source")
        let destinationURL = try standardizedFileURL(request.destination.url, role: "destination")

        try requireContained(sourceURL, in: artifactRoot, role: "source")
        try requireContained(destinationURL, in: artifactRoot, role: "destination")
        try requireContained(
            destinationURL.deletingLastPathComponent(),
            in: artifactRoot,
            role: "destinationParent",
            allowRoot: true
        )
        guard sourceURL.path != destinationURL.path else {
            throw PublicationError.destinationMatchesSource(sourceURL.path)
        }
        try validateSource(sourceURL)
        guard isSHA256Digest(request.expectedSourceDigest) else {
            throw PublicationError.invalidExpectedSourceDigest(request.expectedSourceDigest)
        }
        if let destinationDigest = request.destination.contentHash,
           destinationDigest != request.expectedSourceDigest {
            throw PublicationError.destinationDigestMismatch(
                expected: request.expectedSourceDigest,
                actual: destinationDigest
            )
        }
        let sourceReference = try checkpointReference(
            checkpointID: request.candidateID,
            checkpointURL: sourceURL,
            artifactRoot: artifactRoot
        )
        guard sourceReference.sha256Digest == request.expectedSourceDigest else {
            throw PublicationError.sourceDigestMismatch(
                expected: request.expectedSourceDigest,
                actual: sourceReference.sha256Digest
            )
        }
        try validateBundle(at: sourceURL)

        let destinationParent = destinationURL.deletingLastPathComponent()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        let temporaryURL = destinationParent.appendingPathComponent(
            ".\(destinationURL.lastPathComponent)-\(UUID().uuidString).publishing",
            isDirectory: true
        )
        let backupURL = destinationParent.appendingPathComponent(
            ".\(destinationURL.lastPathComponent)-\(UUID().uuidString).rollback",
            isDirectory: true
        )
        let destinationExisted = fileManager.fileExists(atPath: destinationURL.path)
        var backupReference: EvolutionCheckpointReference?
        var backupReady = false
        do {
            try fileManager.copyItem(at: sourceURL, to: temporaryURL)
            _ = try validateCopiedBundle(
                at: temporaryURL,
                expectedDigest: request.expectedSourceDigest,
                candidateID: request.candidateID,
                artifactRoot: artifactRoot
            )
            if fileManager.fileExists(atPath: destinationURL.path) {
                let currentReference = try checkpointReference(
                    checkpointID: request.candidateID,
                    checkpointURL: destinationURL,
                    artifactRoot: artifactRoot
                )
                try fileManager.copyItem(at: destinationURL, to: backupURL)
                let copiedBackupReference = try checkpointReference(
                    checkpointID: request.candidateID,
                    checkpointURL: backupURL,
                    artifactRoot: artifactRoot
                )
                guard copiedBackupReference.sha256Digest == currentReference.sha256Digest else {
                    throw PublicationError.copiedDigestMismatch(
                        expected: currentReference.sha256Digest,
                        actual: copiedBackupReference.sha256Digest
                    )
                }
                backupReference = currentReference
                backupReady = true
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
            let destinationReference = try validateCopiedBundle(
                at: destinationURL,
                expectedDigest: request.expectedSourceDigest,
                candidateID: request.candidateID,
                artifactRoot: artifactRoot
            )
            if backupReady {
                try removeItemIfPresent(backupURL, fileManager: fileManager)
            }
            return CheckpointPublicationReceipt(
                runID: request.runID,
                candidateID: request.candidateID,
                sourceReference: sourceReference,
                destinationReference: destinationReference
            )
        } catch {
            let primaryError = error
            do {
                try rollback(
                    destinationURL: destinationURL,
                    backupURL: backupURL,
                    backupReference: backupReference,
                    backupReady: backupReady,
                    destinationExisted: destinationExisted,
                    candidateID: request.candidateID,
                    artifactRoot: artifactRoot,
                    fileManager: fileManager
                )
                try removeItemIfPresent(temporaryURL, fileManager: fileManager)
                try removeItemIfPresent(backupURL, fileManager: fileManager)
            } catch let rollbackError {
                throw PublicationError.rollbackFailed(
                    primary: String(describing: primaryError),
                    rollback: String(describing: rollbackError)
                )
            }
            throw primaryError
        }
    }

    private func rollback(
        destinationURL: URL,
        backupURL: URL,
        backupReference: EvolutionCheckpointReference?,
        backupReady: Bool,
        destinationExisted: Bool,
        candidateID: String,
        artifactRoot: URL,
        fileManager: FileManager
    ) throws {
        if backupReady, let backupReference {
            try removeItemIfPresent(destinationURL, fileManager: fileManager)
            try fileManager.moveItem(at: backupURL, to: destinationURL)
            let restoredReference = try checkpointReference(
                checkpointID: candidateID,
                checkpointURL: destinationURL,
                artifactRoot: artifactRoot
            )
            guard restoredReference.sha256Digest == backupReference.sha256Digest else {
                throw PublicationError.copiedDigestMismatch(
                    expected: backupReference.sha256Digest,
                    actual: restoredReference.sha256Digest
                )
            }
        } else if !destinationExisted, fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
    }

    private func removeItemIfPresent(_ url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw PublicationError.cleanupFailed(path: url.path, reason: String(describing: error))
        }
    }

    private func standardizedFileURL(_ url: URL, role: String) throws -> URL {
        guard url.isFileURL else {
            throw PublicationError.nonFileURL(role: role, url: url.absoluteString)
        }
        return url.standardizedFileURL
    }

    private func requireContained(
        _ url: URL,
        in root: URL,
        role: String,
        allowRoot: Bool = false
    ) throws {
        let rootPath = root.resolvingSymlinksInPath().path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let path = url.resolvingSymlinksInPath().path
        guard (allowRoot && path == rootPath) || (path.hasPrefix(rootPrefix) && path != rootPath) else {
            throw PublicationError.pathOutsideArtifactRoot(role: role, path: path, root: rootPath)
        }
    }

    private func validateSource(_ sourceURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw PublicationError.sourceMissing(sourceURL.path)
        }
        let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true {
            throw PublicationError.sourceIsSymbolicLink(sourceURL.path)
        }
        guard values.isDirectory == true else {
            throw PublicationError.sourceIsNotDirectory(sourceURL.path)
        }
    }

    private func validateCopiedBundle(
        at url: URL,
        expectedDigest: String,
        candidateID: String,
        artifactRoot: URL
    ) throws -> EvolutionCheckpointReference {
        try validateBundle(at: url)
        let reference = try checkpointReference(
            checkpointID: candidateID,
            checkpointURL: url,
            artifactRoot: artifactRoot
        )
        guard reference.sha256Digest == expectedDigest else {
            throw PublicationError.copiedDigestMismatch(
                expected: expectedDigest,
                actual: reference.sha256Digest
            )
        }
        return reference
    }

    private func validateBundle(at url: URL) throws {
        do {
            try validator.validatePublicationBundle(at: url)
        } catch {
            throw PublicationError.bundleValidationFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }
    }

    private func checkpointReference(
        checkpointID: String,
        checkpointURL: URL,
        artifactRoot: URL
    ) throws -> EvolutionCheckpointReference {
        do {
            return try EvolutionCheckpointIntegrity().reference(
                checkpointID: checkpointID,
                checkpointURL: checkpointURL,
                artifactRoot: artifactRoot
            )
        } catch {
            throw PublicationError.checkpointIntegrityFailed(
                path: checkpointURL.path,
                reason: String(describing: error)
            )
        }
    }

    private func isSHA256Digest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}
