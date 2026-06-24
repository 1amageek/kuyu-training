import Foundation
import KuyuEvolution
import KuyuTrainingValidation

public enum CheckpointEvaluationArtifactCompatibilityFailure: Sendable, Equatable {
    case schemaVersionMismatch(expected: Int, actual: Int)
    case taskMismatch(expected: String, actual: String)
    case profileMismatch(expected: String, actual: String)
    case checkpointMismatch(expected: String, actual: String)
    case nonFiniteMetric(String)
    case failedPolicy([String])
    case missingTaskQuality(String)
    case missingExpectedTaskQuality(scenarioID: String, seed: UInt64)
    case unexpectedTaskQuality(scenarioID: String, seed: UInt64)
    case duplicateExpectedTaskQuality(scenarioID: String, seed: UInt64)
    case duplicateTaskQuality(scenarioID: String, seed: UInt64)
    case duplicateScenarioHorizon(scenarioID: String, seed: UInt64)
    case missingScenarioHorizon(scenarioID: String, seed: UInt64)
    case unexpectedScenarioHorizon(scenarioID: String, seed: UInt64)
    case invalidScenarioHorizon(scenarioID: String, seed: UInt64)
    case qualityTaskMismatch(expected: String, actual: String)
    case qualityEvaluatorMismatch(expected: String, actual: String)
    case failedTaskQuality(scenarioID: String, reasons: [String])

    public var issueCode: String {
        switch self {
        case .schemaVersionMismatch: "schema-mismatch"
        case .taskMismatch: "task-mismatch"
        case .profileMismatch: "profile-mismatch"
        case .checkpointMismatch: "checkpoint-mismatch"
        case .nonFiniteMetric: "non-finite"
        case .failedPolicy: "failed"
        case .missingTaskQuality: "missing-task-quality"
        case .missingExpectedTaskQuality: "missing-expected-task-quality"
        case .unexpectedTaskQuality: "unexpected-task-quality"
        case .duplicateExpectedTaskQuality: "duplicate-expected-task-quality"
        case .duplicateTaskQuality: "duplicate-task-quality"
        case .duplicateScenarioHorizon: "duplicate-scenario-horizon"
        case .missingScenarioHorizon: "missing-scenario-horizon"
        case .unexpectedScenarioHorizon: "unexpected-scenario-horizon"
        case .invalidScenarioHorizon: "invalid-scenario-horizon"
        case .qualityTaskMismatch: "quality-task-mismatch"
        case .qualityEvaluatorMismatch: "quality-evaluator-mismatch"
        case .failedTaskQuality: "quality-failed"
        }
    }

    public var detailDescription: String {
        switch self {
        case .schemaVersionMismatch(let expected, let actual):
            "expected=\(expected) actual=\(actual)"
        case .taskMismatch(let expected, let actual):
            "expected=\(expected) actual=\(actual)"
        case .profileMismatch(let expected, let actual):
            "expected=\(expected) actual=\(actual)"
        case .checkpointMismatch(let expected, let actual):
            "expected=\(expected) actual=\(actual)"
        case .nonFiniteMetric(let metric):
            "metric=\(metric)"
        case .failedPolicy(let failures):
            "failures=\(failures.joined(separator: ","))"
        case .missingTaskQuality(let task):
            "task=\(task)"
        case .missingExpectedTaskQuality(let scenarioID, let seed),
             .unexpectedTaskQuality(let scenarioID, let seed),
             .duplicateExpectedTaskQuality(let scenarioID, let seed),
             .duplicateTaskQuality(let scenarioID, let seed),
             .duplicateScenarioHorizon(let scenarioID, let seed),
             .missingScenarioHorizon(let scenarioID, let seed),
             .unexpectedScenarioHorizon(let scenarioID, let seed),
             .invalidScenarioHorizon(let scenarioID, let seed):
            "scenario=\(scenarioID) seed=\(seed)"
        case .qualityTaskMismatch(let expected, let actual):
            "expected=\(expected) actual=\(actual)"
        case .qualityEvaluatorMismatch(let expected, let actual):
            "expected=\(expected) actual=\(actual)"
        case .failedTaskQuality(let scenarioID, let reasons):
            "scenario=\(scenarioID) failures=\(reasons.joined(separator: ","))"
        }
    }

    init(validationError: CheckpointEvaluationArtifactValidator.ValidationError) {
        switch validationError {
        case .schemaVersionMismatch(let expected, let actual):
            self = .schemaVersionMismatch(expected: expected, actual: actual)
        case .taskMismatch(let expected, let actual):
            self = .taskMismatch(expected: expected, actual: actual)
        case .profileMismatch(let expected, let actual):
            self = .profileMismatch(expected: expected, actual: actual)
        case .checkpointMismatch(let expected, let actual):
            self = .checkpointMismatch(expected: expected, actual: actual)
        case .nonFiniteMetric(let metric):
            self = .nonFiniteMetric(metric)
        case .failedPolicy(let failures):
            self = .failedPolicy(failures)
        case .missingTaskQuality(let task):
            self = .missingTaskQuality(task)
        case .missingExpectedTaskQuality(let scenarioID, let seed):
            self = .missingExpectedTaskQuality(scenarioID: scenarioID, seed: seed)
        case .unexpectedTaskQuality(let scenarioID, let seed):
            self = .unexpectedTaskQuality(scenarioID: scenarioID, seed: seed)
        case .duplicateExpectedTaskQuality(let scenarioID, let seed):
            self = .duplicateExpectedTaskQuality(scenarioID: scenarioID, seed: seed)
        case .duplicateTaskQuality(let scenarioID, let seed):
            self = .duplicateTaskQuality(scenarioID: scenarioID, seed: seed)
        case .duplicateScenarioHorizon(let scenarioID, let seed):
            self = .duplicateScenarioHorizon(scenarioID: scenarioID, seed: seed)
        case .missingScenarioHorizon(let scenarioID, let seed):
            self = .missingScenarioHorizon(scenarioID: scenarioID, seed: seed)
        case .unexpectedScenarioHorizon(let scenarioID, let seed):
            self = .unexpectedScenarioHorizon(scenarioID: scenarioID, seed: seed)
        case .invalidScenarioHorizon(let scenarioID, let seed):
            self = .invalidScenarioHorizon(scenarioID: scenarioID, seed: seed)
        case .qualityTaskMismatch(let expected, let actual):
            self = .qualityTaskMismatch(expected: expected, actual: actual)
        case .qualityEvaluatorMismatch(let expected, let actual):
            self = .qualityEvaluatorMismatch(expected: expected, actual: actual)
        case .failedTaskQuality(let scenarioID, let reasons):
            self = .failedTaskQuality(scenarioID: scenarioID, reasons: reasons)
        }
    }
}

public struct CheckpointEvaluationArtifactCompatibilityRequest: Sendable, Equatable {
    public let artifactDirectory: URL
    public let expectedProfile: TaskEvaluationProfile
    public let expectedCheckpointPath: String
    public let requiresPolicyPass: Bool

    public init(
        artifactDirectory: URL,
        expectedProfile: TaskEvaluationProfile,
        expectedCheckpointPath: String,
        requiresPolicyPass: Bool
    ) {
        self.artifactDirectory = artifactDirectory
        self.expectedProfile = expectedProfile
        self.expectedCheckpointPath = expectedCheckpointPath
        self.requiresPolicyPass = requiresPolicyPass
    }
}

public struct GeneratedTrainingArtifactCompatibilityRequest: Sendable, Equatable {
    public let runArtifactDirectory: URL?
    public let probeArtifactDirectory: URL?
    public let evolutionArtifactDirectory: URL?
    public let checkpointEvaluation: CheckpointEvaluationArtifactCompatibilityRequest?

    public init(
        runArtifactDirectory: URL? = nil,
        probeArtifactDirectory: URL? = nil,
        evolutionArtifactDirectory: URL? = nil,
        checkpointEvaluation: CheckpointEvaluationArtifactCompatibilityRequest? = nil
    ) {
        self.runArtifactDirectory = runArtifactDirectory
        self.probeArtifactDirectory = probeArtifactDirectory
        self.evolutionArtifactDirectory = evolutionArtifactDirectory
        self.checkpointEvaluation = checkpointEvaluation
    }
}

public struct GeneratedTrainingArtifactCompatibilityReport: Sendable, Equatable {
    public let runArtifacts: TrainingRunArtifactBundle?
    public let probeArtifacts: TrainingProbeArtifactBundle?
    public let evolutionArtifacts: EvolutionRunArtifactBundle?
    public let checkpointEvaluationArtifact: CheckpointEvaluationArtifact?

    public init(
        runArtifacts: TrainingRunArtifactBundle? = nil,
        probeArtifacts: TrainingProbeArtifactBundle? = nil,
        evolutionArtifacts: EvolutionRunArtifactBundle? = nil,
        checkpointEvaluationArtifact: CheckpointEvaluationArtifact? = nil
    ) {
        self.runArtifacts = runArtifacts
        self.probeArtifacts = probeArtifacts
        self.evolutionArtifacts = evolutionArtifacts
        self.checkpointEvaluationArtifact = checkpointEvaluationArtifact
    }
}

public struct GeneratedTrainingArtifactCompatibilityVerifier: Sendable {
    public enum VerificationError: Error, Sendable, Equatable {
        case emptyRequest
        case missingEvolutionArtifact(String)
        case invalidEvolutionArtifact(String)
        case missingCheckpointEvaluationArtifact(String)
        case invalidCheckpointEvaluationArtifact(CheckpointEvaluationArtifactCompatibilityFailure)
        case incompatibleRunAndProbeArtifacts(runID: String, probeTrainingRunID: String)
    }

    private let runValidator: TrainingRunArtifactValidator
    private let probeValidator: TrainingProbeArtifactValidator
    private let evolutionValidator: EvolutionRunArtifactValidator

    public init(
        runValidator: TrainingRunArtifactValidator = TrainingRunArtifactValidator(),
        probeValidator: TrainingProbeArtifactValidator = TrainingProbeArtifactValidator(),
        evolutionValidator: EvolutionRunArtifactValidator = EvolutionRunArtifactValidator()
    ) {
        self.runValidator = runValidator
        self.probeValidator = probeValidator
        self.evolutionValidator = evolutionValidator
    }

    public func verify(
        _ request: GeneratedTrainingArtifactCompatibilityRequest
    ) throws -> GeneratedTrainingArtifactCompatibilityReport {
        guard request.runArtifactDirectory != nil
            || request.probeArtifactDirectory != nil
            || request.evolutionArtifactDirectory != nil
            || request.checkpointEvaluation != nil else {
            throw VerificationError.emptyRequest
        }
        let runArtifacts = try request.runArtifactDirectory.map(loadRunArtifacts)
        let probeArtifacts = try request.probeArtifactDirectory.map(loadProbeArtifacts)
        let evolutionArtifacts = try request.evolutionArtifactDirectory.map(loadEvolutionArtifacts)
        let checkpointEvaluationArtifact = try request.checkpointEvaluation.map(loadCheckpointEvaluationArtifact)
        try validateCompatibility(runArtifacts: runArtifacts, probeArtifacts: probeArtifacts)
        return GeneratedTrainingArtifactCompatibilityReport(
            runArtifacts: runArtifacts,
            probeArtifacts: probeArtifacts,
            evolutionArtifacts: evolutionArtifacts,
            checkpointEvaluationArtifact: checkpointEvaluationArtifact
        )
    }

    public func loadRunArtifacts(from artifactDirectory: URL) throws -> TrainingRunArtifactBundle {
        try runValidator.loadAndValidate(from: artifactDirectory)
    }

    public func loadProbeArtifacts(from artifactDirectory: URL) throws -> TrainingProbeArtifactBundle {
        try probeValidator.loadAndValidate(from: artifactDirectory)
    }

    public func loadEvolutionArtifacts(from artifactDirectory: URL) throws -> EvolutionRunArtifactBundle {
        do {
            return try evolutionValidator.loadAndValidate(from: artifactDirectory)
        } catch EvolutionRunArtifactValidator.ValidationError.missingFile(let fileName) {
            throw VerificationError.missingEvolutionArtifact(fileName)
        } catch let error as EvolutionRunArtifactValidator.ValidationError {
            throw VerificationError.invalidEvolutionArtifact(String(describing: error))
        }
    }

    public func loadCheckpointEvaluationArtifact(
        _ request: CheckpointEvaluationArtifactCompatibilityRequest
    ) throws -> CheckpointEvaluationArtifact {
        let url = request.artifactDirectory.appendingPathComponent(CheckpointEvaluationArtifact.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VerificationError.missingCheckpointEvaluationArtifact(CheckpointEvaluationArtifact.fileName)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let artifact = try decoder.decode(CheckpointEvaluationArtifact.self, from: Data(contentsOf: url))
        try validateCheckpointEvaluationArtifact(
            artifact,
            expectedProfile: request.expectedProfile,
            expectedCheckpointPath: request.expectedCheckpointPath,
            requiresPolicyPass: request.requiresPolicyPass
        )
        return artifact
    }

    public func validateCheckpointEvaluationArtifact(
        _ artifact: CheckpointEvaluationArtifact,
        expectedProfile: TaskEvaluationProfile,
        expectedCheckpointPath: String,
        requiresPolicyPass: Bool
    ) throws {
        do {
            try CheckpointEvaluationArtifactValidator.validate(
                artifact,
                expectedProfile: expectedProfile,
                expectedCheckpointPath: expectedCheckpointPath,
                requiresPolicyPass: requiresPolicyPass
            )
        } catch let error as CheckpointEvaluationArtifactValidator.ValidationError {
            throw VerificationError.invalidCheckpointEvaluationArtifact(
                CheckpointEvaluationArtifactCompatibilityFailure(validationError: error)
            )
        }
    }

    private func validateCompatibility(
        runArtifacts: TrainingRunArtifactBundle?,
        probeArtifacts: TrainingProbeArtifactBundle?
    ) throws {
        guard let runArtifacts, let probeArtifacts else {
            return
        }
        guard runArtifacts.manifest.runID == probeArtifacts.training.manifest.runID else {
            throw VerificationError.incompatibleRunAndProbeArtifacts(
                runID: runArtifacts.manifest.runID,
                probeTrainingRunID: probeArtifacts.training.manifest.runID
            )
        }
    }
}
