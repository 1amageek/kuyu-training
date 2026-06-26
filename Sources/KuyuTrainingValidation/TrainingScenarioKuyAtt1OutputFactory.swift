import KuyuScenarios

public struct TrainingScenarioKuyAtt1OutputFactory: Sendable {
    public init() {}

    public func makeOutput(_ output: TrainingScenarioRunOutput) -> KuyAtt1RunOutput {
        let evaluations = makeEvaluations(summary: output.summary)
        let result = makeResult(summary: output.summary, evaluations: evaluations)
        let summary = ValidationSummary(
            suitePassed: result.passed,
            evaluations: evaluations,
            replay: result.replay,
            manifest: [],
            aggregate: EvaluationAggregate(
                averageRecoveryTime: output.summary.aggregate.averageRecoveryTime,
                worstOvershootDegrees: output.summary.aggregate.worstOvershootDegrees,
                averageHfStabilityScore: output.summary.aggregate.averageHfStabilityScore
            )
        )
        return KuyAtt1RunOutput(
            result: result,
            summary: summary,
            logs: output.logs
        )
    }

    public func makeEvaluations(summary: TrainingScenarioRunSummary) -> [ScenarioEvaluation] {
        summary.evaluations.map { record in
            ScenarioEvaluation(
                scenarioId: record.scenarioID,
                seed: record.seed,
                passed: record.passed,
                maxOmega: record.maxOmega,
                maxTiltDegrees: record.maxTiltDegrees,
                sustainedViolationSeconds: record.sustainedViolationSeconds,
                recoveryTimeSeconds: record.recoveryTimeSeconds,
                overshootDegrees: record.overshootDegrees,
                hfStabilityScore: record.hfStabilityScore,
                failures: record.failures,
                failureReason: record.failureReason,
                failureTime: record.failureTime
            )
        }
    }

    private func makeResult(
        summary: TrainingScenarioRunSummary,
        evaluations: [ScenarioEvaluation]
    ) -> SuiteRunResult {
        let result: SuiteRunResult
        switch summary.replay {
        case .performed(let checks):
            result = SuiteRunResultFactory().makeReplayVerified(
                evaluations: evaluations,
                replayChecks: checks
            )
        case .notPerformed(let reason):
            result = SuiteRunResultFactory().makeEvaluationOnly(
                evaluations: evaluations,
                replaySkippedReason: reason
            )
        }

        return SuiteRunResult(
            evaluations: result.evaluations,
            replay: result.replay,
            passed: summary.suitePassed && !evaluations.isEmpty && result.passed
        )
    }
}
