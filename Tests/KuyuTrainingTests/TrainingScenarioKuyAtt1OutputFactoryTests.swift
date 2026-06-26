import KuyuCore
import KuyuPhysics
import KuyuScenarios
import Testing
@testable import KuyuTraining

@Test func trainingScenarioKuyAtt1OutputFactoryPreservesPerformedReplay() throws {
    let replay = ReplayVerification.performed([
        try makeTrainingScenarioKuyAtt1ReplayCheck(passed: true),
    ])
    let output = try makeTrainingScenarioRunOutput(
        suitePassed: true,
        evaluations: [makeTrainingScenarioKuyAtt1Evaluation(passed: true)],
        replay: replay
    )

    let kuyOutput = TrainingScenarioKuyAtt1OutputFactory().makeOutput(output)

    #expect(kuyOutput.result.passed)
    #expect(kuyOutput.summary.suitePassed)
    #expect(kuyOutput.result.replay == replay)
    #expect(kuyOutput.summary.replay == replay)
    #expect(kuyOutput.summary.evaluations.count == 1)
    #expect(kuyOutput.summary.evaluations[0].scenarioId.rawValue == "training-scenario-projection")
}

@Test func trainingScenarioKuyAtt1OutputFactoryRejectsFailedReplayCheck() throws {
    let output = try makeTrainingScenarioRunOutput(
        suitePassed: true,
        evaluations: [makeTrainingScenarioKuyAtt1Evaluation(passed: true)],
        replay: .performed([
            makeTrainingScenarioKuyAtt1ReplayCheck(
                passed: false,
                issues: ["replay residual exceeded tolerance"]
            ),
        ])
    )

    let kuyOutput = TrainingScenarioKuyAtt1OutputFactory().makeOutput(output)

    #expect(!kuyOutput.result.passed)
    #expect(!kuyOutput.summary.suitePassed)
    #expect(kuyOutput.summary.replay.hasFailures)
}

@Test func trainingScenarioKuyAtt1OutputFactoryRejectsFalseNeutralSummary() throws {
    let output = try makeTrainingScenarioRunOutput(
        suitePassed: false,
        evaluations: [makeTrainingScenarioKuyAtt1Evaluation(passed: true)],
        replay: .notPerformed(reason: "training runtime emitted profile-neutral output")
    )

    let kuyOutput = TrainingScenarioKuyAtt1OutputFactory().makeOutput(output)

    #expect(!kuyOutput.result.passed)
    #expect(!kuyOutput.summary.suitePassed)
    #expect(kuyOutput.summary.replay.notPerformedReason == "training runtime emitted profile-neutral output")
}

@Test func trainingScenarioKuyAtt1OutputFactoryRejectsEmptyEvaluationSummary() throws {
    let output = try makeTrainingScenarioRunOutput(
        suitePassed: true,
        evaluations: [],
        replay: .notPerformed(reason: "empty training runtime output")
    )

    let kuyOutput = TrainingScenarioKuyAtt1OutputFactory().makeOutput(output)

    #expect(!kuyOutput.result.passed)
    #expect(!kuyOutput.summary.suitePassed)
    #expect(kuyOutput.summary.evaluations.isEmpty)
}

private func makeTrainingScenarioRunOutput(
    suitePassed: Bool,
    evaluations: [TrainingScenarioEvaluationRecord],
    replay: ReplayVerification
) throws -> TrainingScenarioRunOutput {
    TrainingScenarioRunOutput(
        summary: TrainingScenarioRunSummary(
            suitePassed: suitePassed,
            evaluations: evaluations,
            aggregate: TrainingScenarioEvaluationAggregate(
                averageRecoveryTime: nil,
                worstOvershootDegrees: evaluations.map(\.maxTiltDegrees).max(),
                averageHfStabilityScore: nil
            ),
            replay: replay
        ),
        logs: [],
        terminalFactsByScenarioKey: [:]
    )
}

private func makeTrainingScenarioKuyAtt1Evaluation(
    passed: Bool
) throws -> TrainingScenarioEvaluationRecord {
    try TrainingScenarioEvaluationRecord(
        scenarioID: "training-scenario-projection",
        seed: 19,
        passed: passed,
        maxOmega: 0.2,
        maxTiltDegrees: 3.0,
        sustainedViolationSeconds: 0.0,
        recoveryTimeSeconds: nil,
        overshootDegrees: nil,
        hfStabilityScore: nil,
        failures: passed ? [] : ["task-failed"]
    )
}

private func makeTrainingScenarioKuyAtt1ReplayCheck(
    passed: Bool,
    issues: [String] = []
) throws -> ReplayCheckResult {
    ReplayCheckResult(
        scenarioId: try ScenarioID("training-scenario-projection"),
        seed: ScenarioSeed(19),
        tier: .tier1,
        passed: passed,
        issues: issues,
        residuals: .zero
    )
}
