import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios

public struct TrainingScenarioEvaluationRecord: Sendable, Codable, Equatable {
    public let scenarioID: ScenarioID
    public let seed: ScenarioSeed
    public let passed: Bool
    public let maxOmega: Double
    public let maxTiltDegrees: Double
    public let sustainedViolationSeconds: Double
    public let recoveryTimeSeconds: Double?
    public let overshootDegrees: Double?
    public let hfStabilityScore: Double?
    public let failures: [String]
    public let failureReason: FailureReason?
    public let failureTime: Double?

    public init(
        scenarioID: ScenarioID,
        seed: ScenarioSeed,
        passed: Bool,
        maxOmega: Double,
        maxTiltDegrees: Double,
        sustainedViolationSeconds: Double,
        recoveryTimeSeconds: Double?,
        overshootDegrees: Double?,
        hfStabilityScore: Double?,
        failures: [String],
        failureReason: FailureReason? = nil,
        failureTime: Double? = nil
    ) {
        self.scenarioID = scenarioID
        self.seed = seed
        self.passed = passed
        self.maxOmega = maxOmega
        self.maxTiltDegrees = maxTiltDegrees
        self.sustainedViolationSeconds = sustainedViolationSeconds
        self.recoveryTimeSeconds = recoveryTimeSeconds
        self.overshootDegrees = overshootDegrees
        self.hfStabilityScore = hfStabilityScore
        self.failures = failures
        self.failureReason = failureReason
        self.failureTime = failureTime
    }

    public init(_ evaluation: ScenarioEvaluation) {
        self.init(
            scenarioID: evaluation.scenarioId,
            seed: evaluation.seed,
            passed: evaluation.passed,
            maxOmega: evaluation.maxOmega,
            maxTiltDegrees: evaluation.maxTiltDegrees,
            sustainedViolationSeconds: evaluation.sustainedViolationSeconds,
            recoveryTimeSeconds: evaluation.recoveryTimeSeconds,
            overshootDegrees: evaluation.overshootDegrees,
            hfStabilityScore: evaluation.hfStabilityScore,
            failures: evaluation.failures,
            failureReason: evaluation.failureReason,
            failureTime: evaluation.failureTime
        )
    }

    public var key: ScenarioKey {
        ScenarioKey(scenarioId: scenarioID, seed: seed)
    }
}

public struct TrainingScenarioEvaluationAggregate: Sendable, Codable, Equatable {
    public let averageRecoveryTime: Double?
    public let worstOvershootDegrees: Double?
    public let averageHfStabilityScore: Double?

    public init(
        averageRecoveryTime: Double?,
        worstOvershootDegrees: Double?,
        averageHfStabilityScore: Double?
    ) {
        self.averageRecoveryTime = averageRecoveryTime
        self.worstOvershootDegrees = worstOvershootDegrees
        self.averageHfStabilityScore = averageHfStabilityScore
    }

    public init(_ aggregate: EvaluationAggregate) {
        self.init(
            averageRecoveryTime: aggregate.averageRecoveryTime,
            worstOvershootDegrees: aggregate.worstOvershootDegrees,
            averageHfStabilityScore: aggregate.averageHfStabilityScore
        )
    }
}

public struct TrainingScenarioRunSummary: Sendable, Codable, Equatable {
    public let suitePassed: Bool
    public let evaluations: [TrainingScenarioEvaluationRecord]
    public let aggregate: TrainingScenarioEvaluationAggregate

    public init(
        suitePassed: Bool,
        evaluations: [TrainingScenarioEvaluationRecord],
        aggregate: TrainingScenarioEvaluationAggregate
    ) {
        self.suitePassed = suitePassed
        self.evaluations = evaluations
        self.aggregate = aggregate
    }

    public init(_ summary: ValidationSummary) {
        self.init(
            suitePassed: summary.suitePassed,
            evaluations: summary.evaluations.map(TrainingScenarioEvaluationRecord.init),
            aggregate: TrainingScenarioEvaluationAggregate(summary.aggregate)
        )
    }
}

public struct TrainingScenarioRunOutput: Sendable, Codable, Equatable {
    public let summary: TrainingScenarioRunSummary
    public let logs: [ScenarioLogEntry]
    public let terminalFactsByScenarioKey: [ScenarioKey: ScenarioTerminalFacts]

    public init(
        summary: TrainingScenarioRunSummary,
        logs: [ScenarioLogEntry],
        terminalFactsByScenarioKey: [ScenarioKey: ScenarioTerminalFacts]
    ) {
        self.summary = summary
        self.logs = logs
        self.terminalFactsByScenarioKey = terminalFactsByScenarioKey
    }

    public init(kuyAtt1 output: KuyAtt1RunOutput) {
        let terminalFactsByScenarioKey = Dictionary(
            output.result.evaluations.map { evaluation in
                (
                    ScenarioKey(scenarioId: evaluation.scenarioId, seed: evaluation.seed),
                    ScenarioTerminalFacts(evaluation: evaluation)
                )
            },
            uniquingKeysWith: { first, _ in first }
        )
        self.init(
            summary: TrainingScenarioRunSummary(output.summary),
            logs: output.logs,
            terminalFactsByScenarioKey: terminalFactsByScenarioKey
        )
    }
}
