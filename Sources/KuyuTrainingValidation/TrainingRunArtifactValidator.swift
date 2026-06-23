import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public struct TrainingRunArtifactBundle: Sendable, Equatable {
    public let artifactDirectory: URL
    public let contract: TrainingRunArtifactContract
    public let manifest: LearningRunManifest
    public let metrics: [TrainingMetricRecord]
    public let scenarioRuns: [TrainingScenarioRunArtifact]
    public let convergence: ConvergenceSummary
    public let checkpointDecision: CheckpointDecision

    public init(
        artifactDirectory: URL,
        contract: TrainingRunArtifactContract,
        manifest: LearningRunManifest,
        metrics: [TrainingMetricRecord],
        scenarioRuns: [TrainingScenarioRunArtifact] = [],
        convergence: ConvergenceSummary,
        checkpointDecision: CheckpointDecision
    ) {
        self.artifactDirectory = artifactDirectory
        self.contract = contract
        self.manifest = manifest
        self.metrics = metrics
        self.scenarioRuns = scenarioRuns
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
        case invalidScenarioRunLine(Int)
        case emptyRunID
        case runIDMismatch(file: String, expected: String, actual: String)
        case nonFiniteMetric(kind: TrainingMetricKind, iteration: Int)
        case invalidWorkerMetric(kind: TrainingMetricKind, iteration: Int)
        case invalidScenarioRunIteration(Int)
        case duplicateScenarioRunIteration(Int)
        case missingScenarioRunEvidence
        case scenarioReplayValidationFailed(iteration: Int, reason: String)
        case nonTerminalManifestState(LearningRunTerminalState)
        case checkpointDecisionConvergenceMismatch(state: CheckpointDecisionState, accepted: Bool)
        case acceptedCheckpointMissingCandidateID
        case acceptedCheckpointMissingCandidateURL
        case acceptedCheckpointMissingPublishedURL
        case stagedCheckpointMissingCandidateID
        case stagedCheckpointMissingCandidateURL
        case outputCheckpointMismatch(expected: String, actual: String?)
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
        let scenarioRuns = try loadScenarioRuns(
            from: artifactDirectory.appendingPathComponent(TrainingScenarioRunArtifact.fileName),
            decoder: decoder
        )

        try validate(
            manifest: manifest,
            metrics: metrics,
            scenarioRuns: scenarioRuns,
            convergence: convergence,
            checkpointDecision: checkpointDecision
        )
        return TrainingRunArtifactBundle(
            artifactDirectory: artifactDirectory,
            contract: contract,
            manifest: manifest,
            metrics: metrics,
            scenarioRuns: scenarioRuns,
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
        scenarioRuns: [TrainingScenarioRunArtifact],
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
        try validateCheckpointDecision(
            manifest: manifest,
            convergence: convergence,
            checkpointDecision: checkpointDecision
        )
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
        try validateScenarioRuns(
            manifest: manifest,
            metrics: metrics,
            scenarioRuns: scenarioRuns
        )
    }

    private func validateScenarioRuns(
        manifest: LearningRunManifest,
        metrics: [TrainingMetricRecord],
        scenarioRuns: [TrainingScenarioRunArtifact]
    ) throws {
        var observedIterations = Set<Int>()
        let replayValidator = TrainingScenarioReplayValidator()
        for scenarioRun in scenarioRuns {
            guard scenarioRun.runID == manifest.runID else {
                throw ValidationError.runIDMismatch(
                    file: TrainingScenarioRunArtifact.fileName,
                    expected: manifest.runID,
                    actual: scenarioRun.runID
                )
            }
            guard scenarioRun.iteration > 0 else {
                throw ValidationError.invalidScenarioRunIteration(scenarioRun.iteration)
            }
            let (inserted, _) = observedIterations.insert(scenarioRun.iteration)
            guard inserted else {
                throw ValidationError.duplicateScenarioRunIteration(scenarioRun.iteration)
            }
            do {
                try replayValidator.validate(summary: scenarioRun.summary)
            } catch {
                throw ValidationError.scenarioReplayValidationFailed(
                    iteration: scenarioRun.iteration,
                    reason: "\(error)"
                )
            }
        }

        let scenarioMetricIterations = Set(metrics.filter { metric in
            metric.kind == .score
                || metric.kind == .passRate
                || metric.kind == .failureRate
                || metric.kind == .safetyViolation
        }.map(\.iteration))
        if !scenarioMetricIterations.isEmpty && observedIterations.isEmpty {
            throw ValidationError.missingScenarioRunEvidence
        }
        for iteration in scenarioMetricIterations {
            guard observedIterations.contains(iteration) else {
                throw ValidationError.invalidScenarioRunIteration(iteration)
            }
        }
        if (manifest.terminalState == .completed || manifest.terminalState == .rejected)
            && observedIterations.isEmpty {
            throw ValidationError.missingScenarioRunEvidence
        }
    }

    private func validateCheckpointDecision(
        manifest: LearningRunManifest,
        convergence: ConvergenceSummary,
        checkpointDecision: CheckpointDecision
    ) throws {
        let acceptsOrStagesCheckpoint = checkpointDecision.state == .accepted
            || checkpointDecision.state == .staged
        guard convergence.accepted == acceptsOrStagesCheckpoint else {
            throw ValidationError.checkpointDecisionConvergenceMismatch(
                state: checkpointDecision.state,
                accepted: convergence.accepted
            )
        }

        switch checkpointDecision.state {
        case .accepted:
            guard let candidateCheckpointID = checkpointDecision.candidateCheckpointID,
                  !candidateCheckpointID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.acceptedCheckpointMissingCandidateID
            }
            guard checkpointDecision.candidateCheckpointURL != nil else {
                throw ValidationError.acceptedCheckpointMissingCandidateURL
            }
            guard checkpointDecision.publishedCheckpointURL != nil else {
                throw ValidationError.acceptedCheckpointMissingPublishedURL
            }
            try validateOutputCheckpointID(manifest: manifest, candidateCheckpointID: candidateCheckpointID)
        case .staged:
            guard let candidateCheckpointID = checkpointDecision.candidateCheckpointID,
                  !candidateCheckpointID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.stagedCheckpointMissingCandidateID
            }
            guard checkpointDecision.candidateCheckpointURL != nil else {
                throw ValidationError.stagedCheckpointMissingCandidateURL
            }
            try validateOutputCheckpointID(manifest: manifest, candidateCheckpointID: candidateCheckpointID)
        case .rejected, .skipped, .failed:
            break
        }
    }

    private func validateOutputCheckpointID(
        manifest: LearningRunManifest,
        candidateCheckpointID: String
    ) throws {
        guard manifest.outputCheckpointID == candidateCheckpointID else {
            throw ValidationError.outputCheckpointMismatch(
                expected: candidateCheckpointID,
                actual: manifest.outputCheckpointID
            )
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

    private func loadScenarioRuns(
        from url: URL,
        decoder: JSONDecoder
    ) throws -> [TrainingScenarioRunArtifact] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError.missingFile(TrainingScenarioRunArtifact.fileName)
        }
        let raw = try String(contentsOf: url, encoding: .utf8)
        var records: [TrainingScenarioRunArtifact] = []
        for (index, line) in raw.split(separator: "\n").enumerated() {
            guard let data = String(line).data(using: .utf8) else {
                throw ValidationError.invalidScenarioRunLine(index + 1)
            }
            do {
                records.append(try decoder.decode(TrainingScenarioRunArtifact.self, from: data))
            } catch {
                throw ValidationError.invalidScenarioRunLine(index + 1)
            }
        }
        return records
    }
}
