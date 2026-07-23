import CryptoKit
import Foundation

public struct TrainingCheckpointReferenceResolver: TrainingCheckpointReferenceResolving {
    public init() {}

    public func reference(
        for checkpointURL: URL
    ) throws -> TrainingRunIterationRecord.CheckpointReference {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: checkpointURL.path,
            isDirectory: &isDirectory
        ) else {
            throw TrainingCheckpointReferenceError.pathMissing(checkpointURL.path)
        }
        var hasher = SHA256()
        if isDirectory.boolValue {
            guard let enumerator = fileManager.enumerator(atPath: checkpointURL.path) else {
                throw TrainingCheckpointReferenceError.enumerationFailed(checkpointURL.path)
            }
            var files: [(relativePath: String, url: URL)] = []
            for case let relativePath as String in enumerator {
                let pathComponents = relativePath.split(separator: "/")
                guard !pathComponents.contains(where: { $0.hasPrefix(".") }) else {
                    continue
                }
                let fileURL = checkpointURL.appendingPathComponent(relativePath)
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                files.append((relativePath, fileURL))
            }
            files.sort { $0.relativePath < $1.relativePath }
            for file in files {
                let content = try Data(contentsOf: file.url)
                hasher.update(data: Data(file.relativePath.utf8))
                hasher.update(data: Data([0]))
                hasher.update(data: content)
                hasher.update(data: Data([0]))
            }
        } else {
            let content = try Data(contentsOf: checkpointURL)
            hasher.update(data: Data(checkpointURL.lastPathComponent.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: content)
            hasher.update(data: Data([0]))
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return TrainingRunIterationRecord.CheckpointReference(
            path: checkpointURL.path,
            sha256Digest: digest,
            digestAlgorithm: .relativePathV2
        )
    }
}
