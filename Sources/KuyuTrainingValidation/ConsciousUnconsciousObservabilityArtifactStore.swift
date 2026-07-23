import Foundation

public struct ConsciousUnconsciousObservabilityArtifactStore: Sendable {
    public enum StoreError: Error, Sendable, Equatable {
        case missingArtifact(String)
        case artifactEscapesRoot(String)
        case invalidArtifact(String)
    }

    private let validator: ConsciousUnconsciousObservabilityArtifactValidator

    public init(
        validator: ConsciousUnconsciousObservabilityArtifactValidator =
            ConsciousUnconsciousObservabilityArtifactValidator()
    ) {
        self.validator = validator
    }

    public func write(
        _ artifact: ConsciousUnconsciousObservabilityArtifact,
        to url: URL
    ) throws -> URL {
        do {
            try validator.validate(artifact)
        } catch {
            throw StoreError.invalidArtifact(String(describing: error))
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(artifact).write(to: url, options: [.atomic])
        return url
    }

    public func write(
        _ artifact: ConsciousUnconsciousObservabilityArtifact,
        to directory: URL,
        fileName: String = ConsciousUnconsciousObservabilityArtifact.fileName
    ) throws -> URL {
        try write(artifact, to: directory.appendingPathComponent(fileName, isDirectory: false))
    }

    public func validatedArtifact(at url: URL) throws -> ConsciousUnconsciousObservabilityArtifact {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StoreError.missingArtifact(url.path)
        }
        do {
            let data = try Data(contentsOf: url)
            let artifact = try JSONDecoder().decode(
                ConsciousUnconsciousObservabilityArtifact.self,
                from: data
            )
            try validator.validate(artifact)
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
    ) throws -> ConsciousUnconsciousObservabilityArtifact {
        let url = rootDirectory.appendingPathComponent(path, isDirectory: false)
        guard Self.isContained(url, in: rootDirectory) else {
            throw StoreError.artifactEscapesRoot(path)
        }
        return try validatedArtifact(at: url)
    }

    private static func isContained(_ url: URL, in directory: URL) -> Bool {
        let containedPath = resolvedPath(url)
        let directoryPath = resolvedPath(directory)
        if containedPath == directoryPath {
            return true
        }
        let prefix = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
        return containedPath.hasPrefix(prefix)
    }

    private static func resolvedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
