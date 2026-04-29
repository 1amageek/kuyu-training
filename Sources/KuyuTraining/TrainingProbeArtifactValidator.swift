import Foundation

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

    public func loadAndValidate(from artifactDirectory: URL) throws -> TrainingProbeArtifactBundle {
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
        let training = try trainingValidator.loadAndValidate(
            from: artifactDirectory.appendingPathComponent("training", isDirectory: true)
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
        if comparison.reloadSucceeded, trained == nil {
            throw ValidationError.missingTrainedRunForReloadedProbe
        }
        if !comparison.reloadSucceeded, trained != nil {
            throw ValidationError.unexpectedTrainedRunForUnreloadedProbe
        }
        if let trained, comparison.trainedPassed != trained.suitePassed {
            throw ValidationError.inconsistentProbeComparison("trainedPassed does not match trained-run suitePassed")
        }
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
        try validateSelectedCheckpoint(comparison)
        try validateProbeMetrics(probeMetrics, manifest: manifest, comparison: comparison)
        try validateRecoveryRelabelStatus(recoveryRelabelStatus)
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
            let loaded = try TrainingDataset.load(from: dataset)
            if loaded.metadata.recordCount <= 0 || loaded.records.isEmpty {
                throw ValidationError.invalidRecoveryRelabelStatus("recovery dataset is empty")
            }
        }
    }

    private func validateSelectedCheckpoint(_ comparison: TrainingProbeComparison) throws {
        switch comparison.selectedCheckpointRole {
        case .candidate:
            if !comparison.probeAccepted {
                throw ValidationError.inconsistentProbeComparison("candidate checkpoint cannot be selected when probe is rejected")
            }
            if comparison.selectedCheckpointURL == nil {
                throw ValidationError.inconsistentProbeComparison("candidate checkpoint selection requires selectedCheckpointURL")
            }
        case .source:
            if comparison.probeAccepted {
                throw ValidationError.inconsistentProbeComparison("source checkpoint cannot be selected when probe is accepted")
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
        guard let divergenceMetric = metrics.last(where: { $0.kind == .teacherDivergenceRegression }) else {
            return
        }
        let expected = comparison.teacherDivergenceNonRegression ? 0.0 : 1.0
        if divergenceMetric.value != expected {
            throw ValidationError.inconsistentProbeComparison("teacherDivergenceRegression metric does not match comparison")
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
