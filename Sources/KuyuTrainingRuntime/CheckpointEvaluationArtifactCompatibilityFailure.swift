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
