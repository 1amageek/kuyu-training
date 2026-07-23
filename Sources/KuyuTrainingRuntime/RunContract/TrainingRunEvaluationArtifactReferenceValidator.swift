import Foundation

public struct TrainingRunEvaluationArtifactReferenceValidator: Sendable {
    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case emptyKind(iteration: Int)
        case emptyPath(iteration: Int, kind: String)
        case absolutePath(iteration: Int, kind: String, path: String)
        case parentDirectoryEscape(iteration: Int, kind: String, path: String)
        case missingFile(iteration: Int, kind: String, path: String)
        case invalidDigest(iteration: Int, kind: String, digest: String)
        case digestMismatch(
            iteration: Int,
            kind: String,
            path: String,
            expected: String,
            actual: String
        )
        case duplicateKind(iteration: Int, kind: String)
        case duplicatePath(iteration: Int, kind: String, path: String)

        public var description: String {
            switch self {
            case .emptyKind(let iteration):
                return "empty artifact kind at iteration \(iteration)"
            case .emptyPath(let iteration, let kind):
                return "empty artifact path at iteration \(iteration) kind=\(kind)"
            case .absolutePath(let iteration, let kind, let path):
                return "absolute artifact path at iteration \(iteration) kind=\(kind) path=\(path)"
            case .parentDirectoryEscape(let iteration, let kind, let path):
                return "artifact path escapes run directory at iteration \(iteration) kind=\(kind) path=\(path)"
            case .missingFile(let iteration, let kind, let path):
                return "missing artifact file at iteration \(iteration) kind=\(kind) path=\(path)"
            case .invalidDigest(let iteration, let kind, let digest):
                return "invalid artifact digest at iteration \(iteration) kind=\(kind) digest=\(digest)"
            case .digestMismatch(let iteration, let kind, let path, let expected, let actual):
                return "artifact digest mismatch at iteration \(iteration) kind=\(kind) path=\(path) expected=\(expected) actual=\(actual)"
            case .duplicateKind(let iteration, let kind):
                return "duplicate artifact kind at iteration \(iteration) kind=\(kind)"
            case .duplicatePath(let iteration, let kind, let path):
                return "duplicate artifact path at iteration \(iteration) kind=\(kind) path=\(path)"
            }
        }
    }

    public init() {}

    public func validate(
        journal: TrainingRunJournalReadResult,
        runDirectory: URL
    ) throws {
        for record in journal.records {
            guard let evaluation = record.evaluation else {
                continue
            }
            try validate(
                artifacts: evaluation.artifacts,
                iteration: record.iteration,
                runDirectory: runDirectory
            )
        }
    }

    public func validate(
        artifacts: [TrainingRunIterationRecord.EvaluationRecord.ArtifactReference],
        iteration: Int,
        runDirectory: URL
    ) throws {
        var seenKinds = Set<String>()
        var seenPaths = Set<String>()
        for artifact in artifacts {
            try validate(artifact: artifact, iteration: iteration, runDirectory: runDirectory)
            guard seenKinds.insert(artifact.kind).inserted else {
                throw ValidationError.duplicateKind(iteration: iteration, kind: artifact.kind)
            }
            guard seenPaths.insert(artifact.path).inserted else {
                throw ValidationError.duplicatePath(
                    iteration: iteration,
                    kind: artifact.kind,
                    path: artifact.path
                )
            }
        }
    }

    private func validate(
        artifact: TrainingRunIterationRecord.EvaluationRecord.ArtifactReference,
        iteration: Int,
        runDirectory: URL
    ) throws {
        guard !artifact.kind.isEmpty else {
            throw ValidationError.emptyKind(iteration: iteration)
        }
        guard !artifact.path.isEmpty else {
            throw ValidationError.emptyPath(iteration: iteration, kind: artifact.kind)
        }
        guard !artifact.path.hasPrefix("/") else {
            throw ValidationError.absolutePath(
                iteration: iteration,
                kind: artifact.kind,
                path: artifact.path
            )
        }
        let components = artifact.path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains("..") else {
            throw ValidationError.parentDirectoryEscape(
                iteration: iteration,
                kind: artifact.kind,
                path: artifact.path
            )
        }
        let url = runDirectory.appendingPathComponent(artifact.path, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError.missingFile(
                iteration: iteration,
                kind: artifact.kind,
                path: artifact.path
            )
        }
        if let expectedDigest = artifact.sha256Digest {
            guard TrainingRunArtifactDigest.isValidSHA256(expectedDigest) else {
                throw ValidationError.invalidDigest(
                    iteration: iteration,
                    kind: artifact.kind,
                    digest: expectedDigest
                )
            }
            let actualDigest = try TrainingRunArtifactDigest().sha256(at: url)
            guard actualDigest == expectedDigest else {
                throw ValidationError.digestMismatch(
                    iteration: iteration,
                    kind: artifact.kind,
                    path: artifact.path,
                    expected: expectedDigest,
                    actual: actualDigest
                )
            }
        }
    }
}
