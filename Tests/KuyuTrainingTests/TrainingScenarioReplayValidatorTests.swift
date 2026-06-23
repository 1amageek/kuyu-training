import Foundation
import Testing
import KuyuCore
import KuyuPhysics
import KuyuScenarios
@testable import KuyuTraining

@Suite("TrainingScenarioReplayValidator")
struct TrainingScenarioReplayValidatorTests {
    @Test func trainingScenarioRunOutputPreservesReplayVerificationFromKuyAtt1Summary() throws {
        let evaluation = try makeReplayEvaluation(scenarioID: "replay-preserved", seed: 7)
        let check = try makeReplayCheck(scenarioID: "replay-preserved", seed: 7)
        let replay = ReplayVerification.performed([check])
        let output = TrainingScenarioRunOutput(
            kuyAtt1: KuyAtt1RunOutput(
                result: SuiteRunResult(
                    evaluations: [evaluation],
                    replay: replay,
                    passed: true
                ),
                summary: ValidationSummary(
                    suitePassed: true,
                    evaluations: [evaluation],
                    replay: replay,
                    manifest: [],
                    aggregate: EvaluationAggregate.from(evaluations: [evaluation])
                ),
                logs: []
            )
        )

        #expect(output.summary.replay == replay)
        try TrainingScenarioReplayValidator().validate(output)
    }

    @Test func validatorRejectsReplayNotPerformed() throws {
        let summary = try makeReplaySummary(
            evaluations: [makeReplayEvaluation(scenarioID: "not-performed", seed: 1)],
            replay: .notPerformed(reason: "fixture skipped replay")
        )

        #expect(throws: TrainingScenarioReplayValidator.ValidationError.replayNotPerformed(
            reason: "fixture skipped replay"
        )) {
            try TrainingScenarioReplayValidator().validate(summary: summary)
        }
    }

    @Test func validatorRejectsFailedReplayCheck() throws {
        let key = try makeScenarioKey(scenarioID: "failed-replay", seed: 2)
        let summary = try makeReplaySummary(
            evaluations: [makeReplayEvaluation(scenarioID: "failed-replay", seed: 2)],
            replay: .performed([
                makeReplayCheck(
                    scenarioID: "failed-replay",
                    seed: 2,
                    passed: false,
                    issues: ["position residual exceeded tolerance"]
                ),
            ])
        )

        #expect(throws: TrainingScenarioReplayValidator.ValidationError.failedReplayCheck(
            key: key,
            issues: ["position residual exceeded tolerance"]
        )) {
            try TrainingScenarioReplayValidator().validate(summary: summary)
        }
    }

    @Test func validatorRejectsMissingReplayCheck() throws {
        let missing = try makeScenarioKey(scenarioID: "missing-replay", seed: 3)
        let summary = try makeReplaySummary(
            evaluations: [makeReplayEvaluation(scenarioID: "missing-replay", seed: 3)],
            replay: .performed([])
        )

        #expect(throws: TrainingScenarioReplayValidator.ValidationError.missingReplayCheck(missing)) {
            try TrainingScenarioReplayValidator().validate(summary: summary)
        }
    }

    @Test func validatorRejectsEmptyPerformedReplaySummary() {
        let summary = makeReplaySummary(
            evaluations: [],
            replay: .performed([])
        )

        #expect(throws: TrainingScenarioReplayValidator.ValidationError.emptyEvaluationSet) {
            try TrainingScenarioReplayValidator().validate(summary: summary)
        }
    }

    @Test func validatorRejectsUnexpectedReplayCheck() throws {
        let expected = try makeScenarioKey(scenarioID: "expected-replay", seed: 4)
        let unexpected = try makeScenarioKey(scenarioID: "unexpected-replay", seed: 5)
        let summary = try makeReplaySummary(
            evaluations: [makeReplayEvaluation(scenarioID: "expected-replay", seed: 4)],
            replay: .performed([makeReplayCheck(scenarioID: "unexpected-replay", seed: 5)])
        )

        #expect(throws: TrainingScenarioReplayValidator.ValidationError.missingReplayCheck(expected)) {
            try TrainingScenarioReplayValidator().validate(summary: summary)
        }

        let unexpectedOnlySummary = try makeReplaySummary(
            evaluations: [],
            replay: .performed([makeReplayCheck(scenarioID: "unexpected-replay", seed: 5)])
        )
        #expect(throws: TrainingScenarioReplayValidator.ValidationError.unexpectedReplayCheck(unexpected)) {
            try TrainingScenarioReplayValidator().validate(summary: unexpectedOnlySummary)
        }
    }

    @Test func validatorRejectsDuplicateReplayCheck() throws {
        let duplicate = try makeScenarioKey(scenarioID: "duplicate-replay", seed: 6)
        let check = try makeReplayCheck(scenarioID: "duplicate-replay", seed: 6)
        let summary = try makeReplaySummary(
            evaluations: [makeReplayEvaluation(scenarioID: "duplicate-replay", seed: 6)],
            replay: .performed([check, check])
        )

        #expect(throws: TrainingScenarioReplayValidator.ValidationError.duplicateReplayCheck(duplicate)) {
            try TrainingScenarioReplayValidator().validate(summary: summary)
        }
    }

    @Test func legacySummaryDecodeRecordsReplayAsNotPerformed() throws {
        let data = Data("""
        {
          "suitePassed": true,
          "evaluations": [
            {
              "scenarioID": { "rawValue": "legacy-summary" },
              "seed": { "rawValue": 8 },
              "passed": true,
              "maxOmega": 0,
              "maxTiltDegrees": 0,
              "sustainedViolationSeconds": 0,
              "recoveryTimeSeconds": null,
              "overshootDegrees": null,
              "hfStabilityScore": null,
              "failures": [],
              "failureReason": null,
              "failureTime": null
            }
          ],
          "aggregate": {
            "averageRecoveryTime": null,
            "worstOvershootDegrees": null,
            "averageHfStabilityScore": null
          }
        }
        """.utf8)

        let summary = try JSONDecoder().decode(TrainingScenarioRunSummary.self, from: data)
        #expect(summary.replay.notPerformedReason == "Legacy training scenario run summary did not record replay verification.")
        #expect(throws: TrainingScenarioReplayValidator.ValidationError.replayNotPerformed(
            reason: "Legacy training scenario run summary did not record replay verification."
        )) {
            try TrainingScenarioReplayValidator().validate(summary: summary)
        }
    }
}

private func makeReplaySummary(
    evaluations: [ScenarioEvaluation],
    replay: ReplayVerification
) -> TrainingScenarioRunSummary {
    TrainingScenarioRunSummary(
        suitePassed: evaluations.allSatisfy(\.passed),
        evaluations: evaluations.map(TrainingScenarioEvaluationRecord.init),
        aggregate: TrainingScenarioEvaluationAggregate(
            averageRecoveryTime: nil,
            worstOvershootDegrees: nil,
            averageHfStabilityScore: nil
        ),
        replay: replay
    )
}

private func makeReplayEvaluation(
    scenarioID: String,
    seed: UInt64,
    passed: Bool = true
) throws -> ScenarioEvaluation {
    ScenarioEvaluation(
        scenarioId: try ScenarioID(scenarioID),
        seed: ScenarioSeed(seed),
        passed: passed,
        maxOmega: 0,
        maxTiltDegrees: 0,
        sustainedViolationSeconds: passed ? 0 : 1,
        recoveryTimeSeconds: passed ? 0 : nil,
        overshootDegrees: nil,
        hfStabilityScore: nil,
        failures: passed ? [] : ["failed"]
    )
}

private func makeReplayCheck(
    scenarioID: String,
    seed: UInt64,
    passed: Bool = true,
    issues: [String] = []
) throws -> ReplayCheckResult {
    ReplayCheckResult(
        scenarioId: try ScenarioID(scenarioID),
        seed: ScenarioSeed(seed),
        tier: .tier0,
        passed: passed,
        issues: issues,
        residuals: .zero
    )
}

private func makeScenarioKey(scenarioID: String, seed: UInt64) throws -> ScenarioKey {
    ScenarioKey(scenarioId: try ScenarioID(scenarioID), seed: ScenarioSeed(seed))
}
