import Foundation

public struct TrainingRunInspectionArtifactStore: Sendable {
    public enum StoreError: Error, Sendable, Equatable {
        case missingArtifact(String)
        case artifactEscapesRoot(String)
        case invalidArtifact(String)
    }

    private let validator: TrainingRunInspectionArtifactValidator

    public init(
        validator: TrainingRunInspectionArtifactValidator = TrainingRunInspectionArtifactValidator()
    ) {
        self.validator = validator
    }

    @discardableResult
    public func write(
        _ artifact: TrainingRunInspectionArtifact,
        to directory: URL,
        fileName: String = TrainingRunInspectionArtifact.fileName
    ) throws -> URL {
        do {
            try validator.validate(artifact)
        } catch {
            throw StoreError.invalidArtifact(String(describing: error))
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(artifact).write(to: url, options: [.atomic])
        } catch {
            throw StoreError.invalidArtifact(String(describing: error))
        }
        return url
    }

    public func validatedArtifact(at url: URL) throws -> TrainingRunInspectionArtifact {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StoreError.missingArtifact(url.path)
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let artifact = try decoder.decode(
                TrainingRunInspectionArtifact.self,
                from: Data(contentsOf: url)
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
    ) throws -> TrainingRunInspectionArtifact {
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
