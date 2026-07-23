import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public struct TrainingProbeArtifactBundle: Sendable, Equatable {
    public let artifactDirectory: URL
    public let manifest: TrainingProbeManifest
    public let teacher: TrainingProbeRunSummary
    public let initial: TrainingProbeRunSummary
    public let trained: TrainingProbeRunSummary?
    public let comparison: TrainingProbeComparison
    public let probeCheckpointDecision: CheckpointDecision
    public let probeMetrics: [TrainingMetricRecord]
    public let recoveryRelabelStatus: TrainingProbeRecoveryRelabelStatus
    public let training: TrainingRunArtifactBundle

    public init(
        artifactDirectory: URL,
        manifest: TrainingProbeManifest,
        teacher: TrainingProbeRunSummary,
        initial: TrainingProbeRunSummary,
        trained: TrainingProbeRunSummary?,
        comparison: TrainingProbeComparison,
        probeCheckpointDecision: CheckpointDecision,
        probeMetrics: [TrainingMetricRecord] = [],
        recoveryRelabelStatus: TrainingProbeRecoveryRelabelStatus = .skipped(reason: "not-loaded"),
        training: TrainingRunArtifactBundle
    ) {
        self.artifactDirectory = artifactDirectory
        self.manifest = manifest
        self.teacher = teacher
        self.initial = initial
        self.trained = trained
        self.comparison = comparison
        self.probeCheckpointDecision = probeCheckpointDecision
        self.probeMetrics = probeMetrics
        self.recoveryRelabelStatus = recoveryRelabelStatus
        self.training = training
    }
}

public struct TrainingProbeArtifactValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable {
        case missingFile(String)
        case emptyProbeID
        case probeIDMismatch(file: String, expected: String, actual: String)
        case trainingRunIDMismatch(file: String, expected: String, actual: String)
        case nonTerminalManifestState(LearningRunTerminalState)
        case nonFiniteScore(file: String)
        case missingTrainedRunForReloadedProbe
        case unexpectedTrainedRunForUnreloadedProbe
        case checkpointDecisionRunIDMismatch(expected: String, actual: String)
        case inconsistentProbeComparison(String)
        case invalidRecoveryRelabelStatus(String)
    }

    private let trainingValidator: TrainingRunArtifactValidator

    public init(trainingValidator: TrainingRunArtifactValidator = TrainingRunArtifactValidator()) {
        self.trainingValidator = trainingValidator
    }

    public func validatedBundle(in artifactDirectory: URL) throws -> TrainingProbeArtifactBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifest = try decode(
            TrainingProbeManifest.self,
            fileName: "probe-manifest.json",
            directory: artifactDirectory,
            decoder: decoder
        )
        let teacher = try decode(
            TrainingProbeRunSummary.self,
            fileName: "teacher-run.json",
            directory: artifactDirectory,
            decoder: decoder
        )
        let initial = try decode(
            TrainingProbeRunSummary.self,
            fileName: "initial-run.json",
            directory: artifactDirectory,
            decoder: decoder
        )
        let comparison = try decode(
            TrainingProbeComparison.self,
            fileName: "comparison.json",
            directory: artifactDirectory,
            decoder: decoder
        )
        let probeCheckpointDecision = try decode(
            CheckpointDecision.self,
            fileName: "probe-checkpoint-decision.json",
            directory: artifactDirectory,
            decoder: decoder
        )
        let trainedURL = artifactDirectory.appendingPathComponent("trained-run.json")
        let trained = FileManager.default.fileExists(atPath: trainedURL.path)
            ? try decoder.decode(TrainingProbeRunSummary.self, from: Data(contentsOf: trainedURL))
            : nil
        let probeMetrics = try loadProbeMetrics(from: artifactDirectory, decoder: decoder)
        let recoveryRelabelStatus = try decode(
            TrainingProbeRecoveryRelabelStatus.self,
            fileName: "recovery-relabel-status.json",
            directory: artifactDirectory,
            decoder: decoder
        )
        let training = try trainingValidator.validatedBundle(
            in: artifactDirectory.appendingPathComponent("training", isDirectory: true)
        )

        try validate(
            manifest: manifest,
            teacher: teacher,
            initial: initial,
            trained: trained,
            comparison: comparison,
            probeCheckpointDecision: probeCheckpointDecision,
            probeMetrics: probeMetrics,
            recoveryRelabelStatus: recoveryRelabelStatus,
            training: training
        )
        return TrainingProbeArtifactBundle(
            artifactDirectory: artifactDirectory,
            manifest: manifest,
            teacher: teacher,
            initial: initial,
            trained: trained,
            comparison: comparison,
            probeCheckpointDecision: probeCheckpointDecision,
            probeMetrics: probeMetrics,
            recoveryRelabelStatus: recoveryRelabelStatus,
            training: training
        )
    }

    private func validate(
        manifest: TrainingProbeManifest,
        teacher: TrainingProbeRunSummary,
        initial: TrainingProbeRunSummary,
        trained: TrainingProbeRunSummary?,
        comparison: TrainingProbeComparison,
        probeCheckpointDecision: CheckpointDecision,
        probeMetrics: [TrainingMetricRecord],
        recoveryRelabelStatus: TrainingProbeRecoveryRelabelStatus,
        training: TrainingRunArtifactBundle
    ) throws {
        guard !manifest.probeID.isEmpty else {
            throw ValidationError.emptyProbeID
        }
        guard manifest.terminalState != .running else {
            throw ValidationError.nonTerminalManifestState(manifest.terminalState)
        }
        guard comparison.probeID == manifest.probeID else {
            throw ValidationError.probeIDMismatch(
                file: "comparison.json",
                expected: manifest.probeID,
                actual: comparison.probeID
            )
        }
        guard comparison.trainingRunID == manifest.trainingRunID else {
            throw ValidationError.trainingRunIDMismatch(
                file: "comparison.json",
                expected: manifest.trainingRunID,
                actual: comparison.trainingRunID
            )
        }
        guard training.manifest.runID == manifest.trainingRunID else {
            throw ValidationError.trainingRunIDMismatch(
                file: "training/manifest.json",
                expected: manifest.trainingRunID,
                actual: training.manifest.runID
            )
        }
        guard probeCheckpointDecision.runID == manifest.trainingRunID else {
            throw ValidationError.checkpointDecisionRunIDMismatch(
                expected: manifest.trainingRunID,
                actual: probeCheckpointDecision.runID
            )
        }
        try validateFinite(summary: teacher, fileName: "teacher-run.json")
        try validateFinite(summary: initial, fileName: "initial-run.json")
        if let trained {
            try validateFinite(summary: trained, fileName: "trained-run.json")
        }
        guard comparison.teacherScore.isFinite,
              comparison.initialScore.isFinite,
              comparison.trainedScore?.isFinite ?? true,
              comparison.scoreDelta?.isFinite ?? true,
              comparison.safetyViolationDelta?.isFinite ?? true,
              comparison.initialTeacherDriveAverageMAE?.isFinite ?? true,
              comparison.trainedTeacherDriveAverageMAE?.isFinite ?? true,
              comparison.initialTeacherMotorAverageMAE?.isFinite ?? true,
              comparison.trainedTeacherMotorAverageMAE?.isFinite ?? true,
              comparison.initialTeacherFinalAltitudeDelta?.isFinite ?? true,
              comparison.trainedTeacherFinalAltitudeDelta?.isFinite ?? true else {
            throw ValidationError.nonFiniteScore(file: "comparison.json")
        }
        guard manifest.minScoreDelta.isFinite else {
            throw ValidationError.nonFiniteScore(file: "probe-manifest.json")
        }
        if manifest.requireAcceptedCheckpoint && !training.convergence.accepted && trained != nil {
            throw ValidationError.inconsistentProbeComparison(
                "requireAcceptedCheckpoint forbids trained-run evidence before accepted training"
            )
        }
        if comparison.reloadSucceeded, trained == nil {
            throw ValidationError.missingTrainedRunForReloadedProbe
        }
        if !comparison.reloadSucceeded, trained != nil {
            throw ValidationError.unexpectedTrainedRunForUnreloadedProbe
        }
        if let trained, comparison.trainedPassed != trained.suitePassed {
            throw ValidationError.inconsistentProbeComparison("trainedPassed does not match trained-run suitePassed")
        }
        try validateComparison(
            comparison,
            manifest: manifest,
            teacher: teacher,
            initial: initial,
            trained: trained,
            training: training,
            probeCheckpointDecision: probeCheckpointDecision
        )
        if manifest.terminalState == .completed, !comparison.policySatisfied {
            throw ValidationError.inconsistentProbeComparison("completed probe requires a policy-satisfied trained run")
        }
        let expectedProbeAccepted = comparison.trainingAccepted
            && comparison.reloadSucceeded
            && comparison.meetsMinimumDelta
            && comparison.safetyNonRegression
            && comparison.referenceSatisfied
            && comparison.policySatisfied
            && comparison.teacherDivergenceNonRegression
        if comparison.probeAccepted != expectedProbeAccepted {
            throw ValidationError.inconsistentProbeComparison("probeAccepted does not match probe criteria")
        }
        if manifest.terminalState == .completed, !comparison.probeAccepted {
            throw ValidationError.inconsistentProbeComparison("completed probe requires probeAccepted")
        }
        if manifest.terminalState == .completed,
           probeCheckpointDecision.state != .accepted || probeCheckpointDecision.publishedCheckpointURL == nil {
            throw ValidationError.inconsistentProbeComparison(
                "completed probe requires an accepted published checkpoint"
            )
        }
        if manifest.terminalState == .failed,
           comparison.probeAccepted,
           probeCheckpointDecision.state == .accepted,
           probeCheckpointDecision.publishedCheckpointURL != nil {
            throw ValidationError.inconsistentProbeComparison(
                "failed probe cannot include a completed acceptance decision"
            )
        }
        try validateSelectedCheckpoint(
            comparison,
            manifest: manifest,
            probeCheckpointDecision: probeCheckpointDecision
        )
        try validateProbeMetrics(probeMetrics, manifest: manifest, comparison: comparison)
        try validateRecoveryRelabelStatus(recoveryRelabelStatus)
    }

    private func validateComparison(
        _ comparison: TrainingProbeComparison,
        manifest: TrainingProbeManifest,
        teacher: TrainingProbeRunSummary,
        initial: TrainingProbeRunSummary,
        trained: TrainingProbeRunSummary?,
        training: TrainingRunArtifactBundle,
        probeCheckpointDecision: CheckpointDecision
    ) throws {
        let expected = TrainingProbeComparison(
            probeID: manifest.probeID,
            trainingRunID: manifest.trainingRunID,
            teacher: teacher,
            initial: initial,
            trained: trained,
            training: TrainingRunResult(
                manifest: training.manifest,
                metrics: training.metrics,
                convergence: training.convergence,
                checkpointDecision: training.checkpointDecision
            ),
            minScoreDelta: manifest.minScoreDelta,
            requireTeacherPass: manifest.requireTeacherPass,
            requireTrainedPass: manifest.requireTrainedPass,
            sourceCheckpointURL: manifest.sourceCheckpointURL
        ).selectingCheckpoint(from: probeCheckpointDecision)
        guard comparison == expected else {
            throw ValidationError.inconsistentProbeComparison(
                "comparison does not match probe summaries, training result, and manifest contract"
            )
        }
    }

    private func validateRecoveryRelabelStatus(_ status: TrainingProbeRecoveryRelabelStatus) throws {
        if !status.attempted {
            if status.datasetDirectory != nil || status.report != nil {
                throw ValidationError.invalidRecoveryRelabelStatus("skipped recovery relabel cannot include dataset or report")
            }
            return
        }
        guard let directory = status.datasetDirectory else {
            throw ValidationError.invalidRecoveryRelabelStatus("attempted recovery relabel requires datasetDirectory")
        }
        if status.failureReason != nil {
            return
        }
        guard let report = status.report else {
            throw ValidationError.invalidRecoveryRelabelStatus("successful recovery relabel requires report")
        }
        guard report.relabeledEntryCount > 0 else {
            throw ValidationError.invalidRecoveryRelabelStatus("successful recovery relabel requires relabeled entries")
        }
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw ValidationError.invalidRecoveryRelabelStatus("recovery dataset directory does not exist")
        }
        let datasets = try discoverDatasets(in: directory)
        if datasets.count != report.relabeledEntryCount {
            throw ValidationError.invalidRecoveryRelabelStatus("recovery dataset count does not match report")
        }
        for dataset in datasets {
            let loaded: TrainingDataset
            do {
                loaded = try TrainingDatasetContractValidator().validatedDataset(in: dataset)
            } catch let error as TrainingDatasetContractValidator.ValidationError {
                throw ValidationError.invalidRecoveryRelabelStatus("recovery dataset contract violation: \(error)")
            }
            if loaded.metadata.recordCount <= 0 || loaded.records.isEmpty {
                throw ValidationError.invalidRecoveryRelabelStatus("recovery dataset is empty")
            }
        }
    }

    private func validateSelectedCheckpoint(
        _ comparison: TrainingProbeComparison,
        manifest: TrainingProbeManifest,
        probeCheckpointDecision: CheckpointDecision
    ) throws {
        switch comparison.selectedCheckpointRole {
        case .candidate:
            if manifest.terminalState != .completed
                || !comparison.probeAccepted
                || probeCheckpointDecision.state != .accepted {
                throw ValidationError.inconsistentProbeComparison(
                    "candidate checkpoint selection requires completed probe acceptance"
                )
            }
            if comparison.selectedCheckpointURL == nil
                || comparison.selectedCheckpointURL != probeCheckpointDecision.publishedCheckpointURL {
                throw ValidationError.inconsistentProbeComparison(
                    "candidate checkpoint selection must match publishedCheckpointURL"
                )
            }
        case .source:
            if manifest.terminalState == .completed {
                throw ValidationError.inconsistentProbeComparison(
                    "source checkpoint cannot be selected by a completed probe"
                )
            }
            if comparison.sourceCheckpointURL == nil || comparison.selectedCheckpointURL != comparison.sourceCheckpointURL {
                throw ValidationError.inconsistentProbeComparison("source checkpoint selection must match sourceCheckpointURL")
            }
        case .none:
            if comparison.selectedCheckpointURL != nil {
                throw ValidationError.inconsistentProbeComparison("none checkpoint selection cannot include selectedCheckpointURL")
            }
        }
    }

    private func loadProbeMetrics(
        from artifactDirectory: URL,
        decoder: JSONDecoder
    ) throws -> [TrainingMetricRecord] {
        let url = artifactDirectory.appendingPathComponent("probe-metrics.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .filter { !$0.isEmpty }
        return try lines.map { line in
            try decoder.decode(TrainingMetricRecord.self, from: Data(line.utf8))
        }
    }

    private func discoverDatasets(in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.appendingPathComponent("meta.json").path),
           fileManager.fileExists(atPath: directory.appendingPathComponent("records.jsonl").path) {
            return [directory]
        }
        let children = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try children.filter { child in
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            return values.isDirectory == true
                && fileManager.fileExists(atPath: child.appendingPathComponent("meta.json").path)
                && fileManager.fileExists(atPath: child.appendingPathComponent("records.jsonl").path)
        }
    }

    private func validateProbeMetrics(
        _ metrics: [TrainingMetricRecord],
        manifest: TrainingProbeManifest,
        comparison: TrainingProbeComparison
    ) throws {
        guard metrics.allSatisfy({ $0.value.isFinite }) else {
            throw ValidationError.nonFiniteScore(file: "probe-metrics.jsonl")
        }
        guard metrics.allSatisfy({ $0.runID == manifest.trainingRunID }) else {
            throw ValidationError.trainingRunIDMismatch(
                file: "probe-metrics.jsonl",
                expected: manifest.trainingRunID,
                actual: metrics.first { $0.runID != manifest.trainingRunID }?.runID ?? ""
            )
        }
        try validateMetric(
            metrics,
            kind: .scoreDelta,
            expected: comparison.scoreDelta,
            missingMessage: "scoreDelta metric is missing"
        )
        try validateMetric(
            metrics,
            kind: .safetyViolationDelta,
            expected: comparison.safetyViolationDelta,
            missingMessage: "safetyViolationDelta metric is missing"
        )
        try validateMetric(
            metrics,
            kind: .safetyEvidenceAvailable,
            expected: comparison.safetyEvidenceAvailable ? 1.0 : 0.0,
            missingMessage: "safetyEvidenceAvailable metric is missing"
        )
        try validateMetric(
            metrics,
            kind: .safetyRegression,
            expected: comparison.safetyEvidenceAvailable && !comparison.safetyNonRegression ? 1.0 : 0.0,
            missingMessage: "safetyRegression metric is missing"
        )
        try validateMetric(
            metrics,
            kind: .policySatisfied,
            expected: comparison.policySatisfied ? 1.0 : 0.0,
            missingMessage: "policySatisfied metric is missing"
        )
        try validateMetric(
            metrics,
            kind: .teacherDivergenceRegression,
            expected: comparison.teacherDivergenceNonRegression ? 0.0 : 1.0,
            missingMessage: "teacherDivergenceRegression metric is missing"
        )
    }

    private func validateMetric(
        _ metrics: [TrainingMetricRecord],
        kind: TrainingMetricKind,
        expected: Double?,
        missingMessage: String
    ) throws {
        let matchingMetrics = metrics.filter { $0.kind == kind }
        guard let expected else {
            if !matchingMetrics.isEmpty {
                throw ValidationError.inconsistentProbeComparison("\(kind.rawValue) metric is unexpected")
            }
            return
        }
        guard !matchingMetrics.isEmpty else {
            throw ValidationError.inconsistentProbeComparison(missingMessage)
        }
        guard matchingMetrics.count == 1, let metric = matchingMetrics.first else {
            throw ValidationError.inconsistentProbeComparison("\(kind.rawValue) metric is duplicated")
        }
        guard let step = metric.step else {
            throw ValidationError.inconsistentProbeComparison("\(kind.rawValue) metric step is missing")
        }
        if metric.iteration != step {
            throw ValidationError.inconsistentProbeComparison("\(kind.rawValue) metric iteration does not match step")
        }
        guard metric.workerIndex == nil,
              metric.snapshotID == nil,
              metric.rolloutShardURL == nil else {
            throw ValidationError.inconsistentProbeComparison("\(kind.rawValue) metric must be probe-scoped")
        }
        guard metric.iteration >= 0 else {
            throw ValidationError.inconsistentProbeComparison("\(kind.rawValue) metric iteration is invalid")
        }
        if metric.value != expected {
            throw ValidationError.inconsistentProbeComparison("\(kind.rawValue) metric does not match comparison")
        }
    }

    private func validateFinite(summary: TrainingProbeRunSummary, fileName: String) throws {
        guard summary.score.isFinite,
              summary.safetyViolationSeconds.isFinite,
              summary.worstOvershootDegrees?.isFinite ?? true,
              summary.averageRecoveryTime?.isFinite ?? true,
              summary.averageHfStabilityScore?.isFinite ?? true,
              summary.diagnostics.averageDriveActivation?.isFinite ?? true,
              summary.diagnostics.maxDriveActivation?.isFinite ?? true,
              allFinite(summary.diagnostics.averageDriveActivationByIndex),
              allFinite(summary.diagnostics.maxDriveActivationByIndex),
              summary.diagnostics.averageActuatorValue?.isFinite ?? true,
              summary.diagnostics.maxActuatorValue?.isFinite ?? true,
              allFinite(summary.diagnostics.averageActuatorValueByIndex),
              allFinite(summary.diagnostics.maxActuatorValueByIndex),
              summary.diagnostics.averageReflexClampMultiplier?.isFinite ?? true,
              summary.diagnostics.averageReflexDamping?.isFinite ?? true,
              summary.diagnostics.averageReflexDelta?.isFinite ?? true,
              summary.diagnostics.averageMotorRawOutput?.isFinite ?? true,
              summary.diagnostics.averageMotorSaturatedOutput?.isFinite ?? true,
              summary.diagnostics.averageMotorFinalOutput?.isFinite ?? true,
              summary.diagnostics.maxMotorFinalOutput?.isFinite ?? true,
              allFinite(summary.diagnostics.averageMotorFinalOutputByIndex),
              allFinite(summary.diagnostics.maxMotorFinalOutputByIndex),
              summary.diagnostics.minAltitudeZ?.isFinite ?? true,
              summary.diagnostics.maxAltitudeZ?.isFinite ?? true,
              summary.diagnostics.finalAltitudeZ?.isFinite ?? true,
              summary.diagnostics.minVerticalVelocityZ?.isFinite ?? true,
              summary.diagnostics.maxVerticalVelocityZ?.isFinite ?? true,
              summary.diagnostics.finalVerticalVelocityZ?.isFinite ?? true else {
            throw ValidationError.nonFiniteScore(file: fileName)
        }
    }

    private func allFinite(_ values: [Double]?) -> Bool {
        values?.allSatisfy(\.isFinite) ?? true
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
}
