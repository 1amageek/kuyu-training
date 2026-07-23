import CryptoKit
import Foundation

public struct EvolutionAcceptanceEvidenceIntegrity: Sendable {
    public enum IntegrityError: Error, Sendable, Equatable {
        case emptyArtifactType
        case invalidRelativePath(String)
        case pathEscapesAcceptanceDirectory(String)
        case missingFile(String)
        case nonRegularFile(String)
        case symbolicLink(String)
        case invalidDigest(String)
        case invalidByteCount(Int64)
        case byteCountMismatch(path: String, expected: Int64, actual: Int64)
        case digestMismatch(path: String, expected: String, actual: String)
    }

    public init() {}

    public func reference(
        for artifactURL: URL,
        relativeTo acceptanceDirectory: URL,
        artifactType: String
    ) throws -> EvolutionCandidateAcceptanceEvidenceReference {
        guard !artifactType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IntegrityError.emptyArtifactType
        }
        let root = acceptanceDirectory.resolvingSymlinksInPath().standardizedFileURL
        let artifact = artifactURL.resolvingSymlinksInPath().standardizedFileURL
        guard let relativePath = relativePath(of: artifact, within: root) else {
            throw IntegrityError.pathEscapesAcceptanceDirectory(artifactURL.path)
        }
        let values = try artifactURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw IntegrityError.symbolicLink(relativePath)
        }
        guard values.isRegularFile == true else {
            throw IntegrityError.nonRegularFile(relativePath)
        }
        let data = try Data(contentsOf: artifact, options: [.mappedIfSafe])
        return EvolutionCandidateAcceptanceEvidenceReference(
            artifactType: artifactType,
            relativePath: relativePath,
            sha256Digest: Self.sha256Digest(of: data),
            byteCount: Int64(data.count)
        )
    }

    @discardableResult
    public func validatedURL(
        for reference: EvolutionCandidateAcceptanceEvidenceReference,
        in acceptanceDirectory: URL
    ) throws -> URL {
        try validateReferenceFields(reference)
        let root = acceptanceDirectory.resolvingSymlinksInPath().standardizedFileURL
        let unresolved = acceptanceDirectory.appendingPathComponent(reference.relativePath, isDirectory: false)
        guard FileManager.default.fileExists(atPath: unresolved.path) else {
            throw IntegrityError.missingFile(reference.relativePath)
        }
        let values = try unresolved.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw IntegrityError.symbolicLink(reference.relativePath)
        }
        guard values.isRegularFile == true else {
            throw IntegrityError.nonRegularFile(reference.relativePath)
        }
        let artifact = unresolved.resolvingSymlinksInPath().standardizedFileURL
        guard relativePath(of: artifact, within: root) == reference.relativePath else {
            throw IntegrityError.pathEscapesAcceptanceDirectory(reference.relativePath)
        }
        let data = try Data(contentsOf: artifact, options: [.mappedIfSafe])
        let actualByteCount = Int64(data.count)
        guard actualByteCount == reference.byteCount else {
            throw IntegrityError.byteCountMismatch(
                path: reference.relativePath,
                expected: reference.byteCount,
                actual: actualByteCount
            )
        }
        let actualDigest = Self.sha256Digest(of: data)
        guard actualDigest == reference.sha256Digest else {
            throw IntegrityError.digestMismatch(
                path: reference.relativePath,
                expected: reference.sha256Digest,
                actual: actualDigest
            )
        }
        return artifact
    }

    public static func sha256Digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func validateReferenceFields(
        _ reference: EvolutionCandidateAcceptanceEvidenceReference
    ) throws {
        guard !reference.artifactType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IntegrityError.emptyArtifactType
        }
        let relativePath = reference.relativePath
        let pathComponents = (relativePath as NSString).pathComponents
        guard !relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !(relativePath as NSString).isAbsolutePath,
              !pathComponents.contains("."),
              !pathComponents.contains("..") else {
            throw IntegrityError.invalidRelativePath(relativePath)
        }
        let digestCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        guard reference.sha256Digest.count == 64,
              reference.sha256Digest.unicodeScalars.allSatisfy(digestCharacters.contains) else {
            throw IntegrityError.invalidDigest(reference.sha256Digest)
        }
        guard reference.byteCount >= 0 else {
            throw IntegrityError.invalidByteCount(reference.byteCount)
        }
    }

    private func relativePath(of artifact: URL, within root: URL) -> String? {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard artifact.path.hasPrefix(rootPath) else { return nil }
        let relativePath = String(artifact.path.dropFirst(rootPath.count))
        guard !relativePath.isEmpty else { return nil }
        return relativePath
    }
}
