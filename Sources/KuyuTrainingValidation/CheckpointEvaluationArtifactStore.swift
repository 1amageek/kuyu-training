import Foundation

public struct CheckpointEvaluationArtifactStore: Sendable {
    public enum StoreError: Error, Sendable, Equatable, CustomStringConvertible {
        case missingArtifact(String)
        case artifactEscapesRoot(String)
        case invalidArtifact(String)

        public var description: String {
            switch self {
            case .missingArtifact(let path):
                return "missing checkpoint evaluation artifact: \(path)"
            case .artifactEscapesRoot(let path):
                return "checkpoint evaluation artifact escapes run directory: \(path)"
            case .invalidArtifact(let reason):
                return "invalid checkpoint evaluation artifact: \(reason)"
            }
        }
    }

    public init() {}

    public func validatedArtifact(at url: URL) throws -> CheckpointEvaluationArtifact {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StoreError.missingArtifact(url.path)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let artifact = try decoder.decode(
                CheckpointEvaluationArtifact.self,
                from: Data(contentsOf: url)
            )
            let profile = try TaskEvaluationProfile.profile(profileID: artifact.profileID)
            try CheckpointEvaluationArtifactValidator.validate(
                artifact,
                expectedProfile: profile,
                expectedCheckpointPath: artifact.checkpointPath,
                requiresPolicyPass: false
            )
            return artifact
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.invalidArtifact(String(describing: error))
        }
    }

    public func validatedArtifact(
        at path: String,
        relativeTo rootDirectory: URL
    ) throws -> CheckpointEvaluationArtifact {
        let url = rootDirectory.appendingPathComponent(path, isDirectory: false)
        guard Self.isContained(url, in: rootDirectory) else {
            throw StoreError.artifactEscapesRoot(path)
        }
        return try validatedArtifact(at: url)
    }

    private static func isContained(_ url: URL, in directory: URL) -> Bool {
        let artifactPath = resolvedPath(url)
        let rootPath = resolvedPath(directory)
        if artifactPath == rootPath {
            return true
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return artifactPath.hasPrefix(prefix)
    }

    private static func resolvedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
