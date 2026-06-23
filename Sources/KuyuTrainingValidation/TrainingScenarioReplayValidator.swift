import KuyuCore
import KuyuPhysics

public struct TrainingScenarioReplayValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable, CustomStringConvertible {
        case emptyEvaluationSet
        case replayNotPerformed(reason: String)
        case duplicateEvaluation(ScenarioKey)
        case duplicateReplayCheck(ScenarioKey)
        case failedReplayCheck(key: ScenarioKey, issues: [String])
        case missingReplayCheck(ScenarioKey)
        case unexpectedReplayCheck(ScenarioKey)

        public var description: String {
            switch self {
            case .emptyEvaluationSet:
                return "empty-scenario-evaluation-set"
            case .replayNotPerformed(let reason):
                return "scenario-replay-not-performed reason=\(reason)"
            case .duplicateEvaluation(let key):
                return "duplicate-scenario-evaluation \(Self.describe(key))"
            case .duplicateReplayCheck(let key):
                return "duplicate-scenario-replay-check \(Self.describe(key))"
            case .failedReplayCheck(let key, let issues):
                let issueSummary = issues.isEmpty ? "unspecified" : issues.joined(separator: ";")
                return "failed-scenario-replay-check \(Self.describe(key)) issues=\(issueSummary)"
            case .missingReplayCheck(let key):
                return "missing-scenario-replay-check \(Self.describe(key))"
            case .unexpectedReplayCheck(let key):
                return "unexpected-scenario-replay-check \(Self.describe(key))"
            }
        }

        private static func describe(_ key: ScenarioKey) -> String {
            "scenario=\(key.scenarioId.rawValue) seed=\(key.seed.rawValue)"
        }
    }

    public init() {}

    public func validate(_ output: TrainingScenarioRunOutput) throws {
        try validate(summary: output.summary)
    }

    public func validate(summary: TrainingScenarioRunSummary) throws {
        var expectedKeys = Set<ScenarioKey>()
        for evaluation in summary.evaluations {
            let (inserted, _) = expectedKeys.insert(evaluation.key)
            guard inserted else {
                throw ValidationError.duplicateEvaluation(evaluation.key)
            }
        }

        let checks: [ReplayCheckResult]
        switch summary.replay {
        case .performed(let performedChecks):
            checks = performedChecks
        case .notPerformed(let reason):
            throw ValidationError.replayNotPerformed(reason: reason)
        }

        var observedKeys = Set<ScenarioKey>()
        for check in checks {
            let key = ScenarioKey(scenarioId: check.scenarioId, seed: check.seed)
            let (inserted, _) = observedKeys.insert(key)
            guard inserted else {
                throw ValidationError.duplicateReplayCheck(key)
            }
            guard check.passed else {
                throw ValidationError.failedReplayCheck(key: key, issues: check.issues)
            }
        }

        guard !expectedKeys.isEmpty || !observedKeys.isEmpty else {
            throw ValidationError.emptyEvaluationSet
        }
        if let missing = expectedKeys.subtracting(observedKeys).sortedForDiagnostics.first {
            throw ValidationError.missingReplayCheck(missing)
        }
        if let unexpected = observedKeys.subtracting(expectedKeys).sortedForDiagnostics.first {
            throw ValidationError.unexpectedReplayCheck(unexpected)
        }
    }
}

private extension Set where Element == ScenarioKey {
    var sortedForDiagnostics: [ScenarioKey] {
        sorted {
            if $0.scenarioId.rawValue == $1.scenarioId.rawValue {
                return $0.seed.rawValue < $1.seed.rawValue
            }
            return $0.scenarioId.rawValue < $1.scenarioId.rawValue
        }
    }
}
