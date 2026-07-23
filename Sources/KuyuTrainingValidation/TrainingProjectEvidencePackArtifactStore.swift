import Foundation
import KuyuPhysics
import KuyuScenarios
import KuyuTrainingContracts

public struct TrainingProjectEvidencePackArtifactStore: Sendable {
    public enum StoreError: Error, Sendable, Equatable {
        case missingEvidencePack(String)
        case evidencePackEscapesRoot(String)
        case missingReferencedRegressionArtifact(String)
        case referencedRegressionArtifactEscapesRoot(String)
        case missingReferencedStressSuiteManifest(String)
        case referencedStressSuiteManifestEscapesRoot(String)
        case invalidReferencedStressSuiteManifest(String)
        case referencedStressSuiteManifestMismatch(String)
        case missingReferencedPhysicsCorpusAcceptance(String)
        case referencedPhysicsCorpusAcceptanceEscapesRoot(String)
        case invalidReferencedPhysicsCorpusAcceptance(String)
        case referencedPhysicsCorpusAcceptanceMismatch(String)
        case missingReferencedObservabilityArtifact(String)
        case referencedObservabilityArtifactEscapesRoot(String)
        case invalidReferencedObservabilityArtifact(String)
        case referencedObservabilityArtifactMismatch(String)
        case invalidEvidencePack(TrainingProjectEvidencePackValidator.ValidationError)
    }

    private let validator: TrainingProjectEvidencePackValidator

    public init(validator: TrainingProjectEvidencePackValidator = TrainingProjectEvidencePackValidator()) {
        self.validator = validator
    }

    public func write(
        _ pack: TrainingProjectEvidencePack,
        to directory: URL,
        requireRegressionArtifactsExist: Bool = true
    ) throws -> URL {
        try validatePack(pack, rootDirectory: directory, requireRegressionArtifactsExist: requireRegressionArtifactsExist)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(TrainingProjectEvidencePack.fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(pack).write(to: url, options: [.atomic])
        return url
    }

    public func writeValidatedPack(
        projectID: String,
        datasetMetadata: [TrainingDatasetMetadata],
        curriculum: LearningProjectCurriculum,
        checkpointDecision: CheckpointDecision,
        regressionArtifacts: [TrainingProjectEvidencePack.RegressionArtifactReference],
        stressSuites: [TrainingProjectEvidencePack.StressSuiteEvidence] = [],
        physicsCorpora: [TrainingProjectEvidencePack.PhysicsCorpusEvidence] = [],
        observabilityArtifacts: [TrainingProjectEvidencePack.ObservabilityArtifactEvidence] = [],
        to directory: URL,
        createdAt: Date = Date()
    ) throws -> TrainingProjectEvidencePack {
        let pack = try validator.makePack(
            projectID: projectID,
            datasetMetadata: datasetMetadata,
            curriculum: curriculum,
            checkpointDecision: checkpointDecision,
            regressionArtifacts: regressionArtifacts,
            stressSuites: stressSuites,
            physicsCorpora: physicsCorpora,
            observabilityArtifacts: observabilityArtifacts,
            createdAt: createdAt
        )
        _ = try write(pack, to: directory)
        return try load(from: directory)
    }

    public func load(
        from directory: URL,
        requireRegressionArtifactsExist: Bool = true
    ) throws -> TrainingProjectEvidencePack {
        let url = directory.appendingPathComponent(TrainingProjectEvidencePack.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StoreError.missingEvidencePack(url.path)
        }
        try validateContainedPath(
            url,
            rootDirectory: directory,
            path: url.path,
            escapingError: StoreError.evidencePackEscapesRoot
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pack = try decoder.decode(TrainingProjectEvidencePack.self, from: Data(contentsOf: url))
        try validatePack(pack, rootDirectory: directory, requireRegressionArtifactsExist: requireRegressionArtifactsExist)
        return pack
    }

    private func validatePack(
        _ pack: TrainingProjectEvidencePack,
        rootDirectory: URL,
        requireRegressionArtifactsExist: Bool
    ) throws {
        do {
            try validator.validate(pack)
        } catch let error as TrainingProjectEvidencePackValidator.ValidationError {
            throw StoreError.invalidEvidencePack(error)
        }
        guard requireRegressionArtifactsExist else { return }
        for artifact in pack.regressionArtifacts {
            let url = rootDirectory.appendingPathComponent(artifact.path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw StoreError.missingReferencedRegressionArtifact(artifact.path)
            }
            try validateContainedPath(
                url,
                rootDirectory: rootDirectory,
                path: artifact.path,
                escapingError: StoreError.referencedRegressionArtifactEscapesRoot
            )
        }
        try validateReferencedStressSuites(pack.stressSuites, rootDirectory: rootDirectory)
        try validateReferencedPhysicsCorpora(pack.physicsCorpora, rootDirectory: rootDirectory)
        try validateReferencedObservabilityArtifacts(pack.observabilityArtifacts, rootDirectory: rootDirectory)
    }

    private func validateReferencedStressSuites(
        _ stressSuites: [TrainingProjectEvidencePack.StressSuiteEvidence],
        rootDirectory: URL
    ) throws {
        let store = StressSuiteManifestArtifactStore()
        for suite in stressSuites {
            let url = rootDirectory.appendingPathComponent(suite.path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw StoreError.missingReferencedStressSuiteManifest(suite.path)
            }
            try validateContainedPath(
                url,
                rootDirectory: rootDirectory,
                path: suite.path,
                escapingError: StoreError.referencedStressSuiteManifestEscapesRoot
            )
            let manifest: StressSuiteManifest
            do {
                manifest = try store.validatedManifest(at: url, artifactRoot: rootDirectory)
            } catch {
                throw StoreError.invalidReferencedStressSuiteManifest(suite.path)
            }
            guard TrainingProjectEvidencePack.StressSuiteEvidence(
                manifest: manifest,
                path: suite.path
            ) == suite else {
                throw StoreError.referencedStressSuiteManifestMismatch(suite.path)
            }
        }
    }

    private func validateReferencedPhysicsCorpora(
        _ physicsCorpora: [TrainingProjectEvidencePack.PhysicsCorpusEvidence],
        rootDirectory: URL
    ) throws {
        let store = DescriptorCorpusAcceptanceArtifactStore()
        for corpus in physicsCorpora {
            let url = rootDirectory.appendingPathComponent(corpus.path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw StoreError.missingReferencedPhysicsCorpusAcceptance(corpus.path)
            }
            try validateContainedPath(
                url,
                rootDirectory: rootDirectory,
                path: corpus.path,
                escapingError: StoreError.referencedPhysicsCorpusAcceptanceEscapesRoot
            )
            let summary: DescriptorCorpusAcceptanceSummary
            do {
                summary = try store.validatedSummary(at: url)
            } catch {
                throw StoreError.invalidReferencedPhysicsCorpusAcceptance(corpus.path)
            }
            guard TrainingProjectEvidencePack.PhysicsCorpusEvidence(
                summary: summary,
                path: corpus.path
            ) == corpus else {
                throw StoreError.referencedPhysicsCorpusAcceptanceMismatch(corpus.path)
            }
        }
    }

    private func validateReferencedObservabilityArtifacts(
        _ artifacts: [TrainingProjectEvidencePack.ObservabilityArtifactEvidence],
        rootDirectory: URL
    ) throws {
        let store = ConsciousUnconsciousObservabilityArtifactStore()
        for artifact in artifacts {
            let url = rootDirectory.appendingPathComponent(artifact.path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw StoreError.missingReferencedObservabilityArtifact(artifact.path)
            }
            try validateContainedPath(
                url,
                rootDirectory: rootDirectory,
                path: artifact.path,
                escapingError: StoreError.referencedObservabilityArtifactEscapesRoot
            )
            let observed: ConsciousUnconsciousObservabilityArtifact
            do {
                observed = try store.validatedArtifact(at: url)
            } catch {
                throw StoreError.invalidReferencedObservabilityArtifact(artifact.path)
            }
            guard TrainingProjectEvidencePack.ObservabilityArtifactEvidence(
                artifact: observed,
                path: artifact.path
            ) == artifact else {
                throw StoreError.referencedObservabilityArtifactMismatch(artifact.path)
            }
        }
    }

    private func validateContainedPath(
        _ url: URL,
        rootDirectory: URL,
        path: String,
        escapingError: (String) -> StoreError
    ) throws {
        guard Self.isContained(url, in: rootDirectory) else {
            throw escapingError(path)
        }
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
