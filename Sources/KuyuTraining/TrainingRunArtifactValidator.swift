import Foundation

public struct TrainingRunArtifactBundle: Sendable, Equatable {
    public let artifactDirectory: URL
    public let contract: TrainingRunArtifactContract
    public let manifest: LearningRunManifest
    public let metrics: [TrainingMetricRecord]
    public let convergence: ConvergenceSummary
    public let checkpointDecision: CheckpointDecision

    public init(
        artifactDirectory: URL,
        contract: TrainingRunArtifactContract,
        manifest: LearningRunManifest,
        metrics: [TrainingMetricRecord],
        convergence: ConvergenceSummary,
        checkpointDecision: CheckpointDecision
    ) {
        self.artifactDirectory = artifactDirectory
        self.contract = contract
        self.manifest = manifest
        self.metrics = metrics
        self.convergence = convergence
        self.checkpointDecision = checkpointDecision
    }
}

public struct TrainingRunArtifactValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable {
        case missingFile(String)
        case unsupportedSchemaVersion(Int)
        case unsupportedContractVersion(Int)
        case invalidMetricLine(Int)
        case emptyRunID
        case runIDMismatch(file: String, expected: String, actual: String)
        case nonFiniteMetric(kind: TrainingMetricKind, iteration: Int)
        case invalidWorkerMetric(kind: TrainingMetricKind, iteration: Int)
        case nonTerminalManifestState(LearningRunTerminalState)
    }

    public init() {}

    public func loadAndValidate(from artifactDirectory: URL) throws -> TrainingRunArtifactBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let contract = try decode(
            TrainingRunArtifactContract.self,
            fileName: TrainingRunArtifactContract.fileName,
            directory: artifactDirectory,
            decoder: decoder
        )
        try validate(contract: contract, directory: artifactDirectory)

        let manifest = try decode(
            LearningRunManifest.self,
            fileName: "manifest.json",
            directory: artifactDirectory,
            decoder: decoder
        )
        let convergence = try decode(
            ConvergenceSummary.self,
            fileName: "convergence.json",
            directory: artifactDirectory,
            decoder: decoder
        )
        let checkpointDecision = try decode(
            CheckpointDecision.self,
            fileName: "checkpoint-decision.json",
            directory: artifactDirectory,
            decoder: decoder
        )
        let metrics = try loadMetrics(
            from: artifactDirectory.appendingPathComponent("metrics.jsonl"),
            decoder: decoder
        )

        try validate(
            manifest: manifest,
            metrics: metrics,
            convergence: convergence,
            checkpointDecision: checkpointDecision
        )
        return TrainingRunArtifactBundle(
            artifactDirectory: artifactDirectory,
            contract: contract,
            manifest: manifest,
            metrics: metrics,
            convergence: convergence,
            checkpointDecision: checkpointDecision
        )
    }

    private func validate(contract: TrainingRunArtifactContract, directory: URL) throws {
        guard contract.schemaVersion == TrainingRunArtifactContract.currentSchemaVersion else {
            throw ValidationError.unsupportedSchemaVersion(contract.schemaVersion)
        }
        guard contract.contractVersion == TrainingRunArtifactContract.currentContractVersion else {
            throw ValidationError.unsupportedContractVersion(contract.contractVersion)
        }
        for fileName in contract.requiredFiles + [TrainingRunArtifactContract.fileName] {
            let path = directory.appendingPathComponent(fileName).path
            guard FileManager.default.fileExists(atPath: path) else {
                throw ValidationError.missingFile(fileName)
            }
        }
    }

    private func validate(
        manifest: LearningRunManifest,
        metrics: [TrainingMetricRecord],
        convergence: ConvergenceSummary,
        checkpointDecision: CheckpointDecision
    ) throws {
        guard !manifest.runID.isEmpty else {
            throw ValidationError.emptyRunID
        }
        guard manifest.terminalState != .running else {
            throw ValidationError.nonTerminalManifestState(manifest.terminalState)
        }
        guard convergence.runID == manifest.runID else {
            throw ValidationError.runIDMismatch(
                file: "convergence.json",
                expected: manifest.runID,
                actual: convergence.runID
            )
        }
        guard checkpointDecision.runID == manifest.runID else {
            throw ValidationError.runIDMismatch(
                file: "checkpoint-decision.json",
                expected: manifest.runID,
                actual: checkpointDecision.runID
            )
        }
        for metric in metrics {
            guard metric.runID == manifest.runID else {
                throw ValidationError.runIDMismatch(
                    file: "metrics.jsonl",
                    expected: manifest.runID,
                    actual: metric.runID
                )
            }
            guard metric.value.isFinite else {
                throw ValidationError.nonFiniteMetric(kind: metric.kind, iteration: metric.iteration)
            }
            if metric.workerIndex != nil || metric.snapshotID != nil || metric.rolloutShardURL != nil {
                guard let workerIndex = metric.workerIndex,
                      workerIndex >= 0,
                      let snapshotID = metric.snapshotID,
                      !snapshotID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      metric.rolloutShardURL != nil else {
                    throw ValidationError.invalidWorkerMetric(kind: metric.kind, iteration: metric.iteration)
                }
            }
        }
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        fileName: String,
        directory: URL,
        decoder: JSONDecoder
    ) throws -> T {
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError.missingFile(fileName)
        }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func loadMetrics(from url: URL, decoder: JSONDecoder) throws -> [TrainingMetricRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError.missingFile("metrics.jsonl")
        }
        let raw = try String(contentsOf: url, encoding: .utf8)
        var records: [TrainingMetricRecord] = []
        for (index, line) in raw.split(separator: "\n").enumerated() {
            guard let data = String(line).data(using: .utf8) else {
                throw ValidationError.invalidMetricLine(index + 1)
            }
            do {
                records.append(try decoder.decode(TrainingMetricRecord.self, from: data))
            } catch {
                throw ValidationError.invalidMetricLine(index + 1)
            }
        }
        return records
    }
}
