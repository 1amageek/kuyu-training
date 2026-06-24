import Foundation
import KuyuScenarios
import KuyuTraining
import Testing

@Test func checkpointEvaluationArtifactValidatorAcceptsValidLiftEvaluation() throws {
    let profile = try TaskEvaluationProfile.profile(task: "lift")
    let artifact = makeCheckpointEvaluationArtifact(profile: profile)

    try CheckpointEvaluationArtifactValidator.validate(
        artifact,
        expectedProfile: profile,
        expectedCheckpointPath: artifact.checkpointPath,
        requiresPolicyPass: true
    )
}

@Test func checkpointEvaluationArtifactValidatorRejectsSchemaMismatch() throws {
    let profile = try TaskEvaluationProfile.profile(task: "lift")
    let artifact = makeCheckpointEvaluationArtifact(profile: profile, schemaVersion: 1)

    do {
        try CheckpointEvaluationArtifactValidator.validate(
            artifact,
            expectedProfile: profile,
            expectedCheckpointPath: artifact.checkpointPath,
            requiresPolicyPass: true
        )
        Issue.record("Expected schema mismatch to throw.")
    } catch CheckpointEvaluationArtifactValidator.ValidationError.schemaVersionMismatch(let expected, let actual) {
        #expect(expected == CheckpointEvaluationArtifact.currentSchemaVersion)
        #expect(actual == 1)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func checkpointEvaluationArtifactValidatorRejectsNonFiniteMetric() throws {
    let profile = try TaskEvaluationProfile.profile(task: "lift")
    let artifact = makeCheckpointEvaluationArtifact(profile: profile, policyScore: .nan)

    do {
        try CheckpointEvaluationArtifactValidator.validate(
            artifact,
            expectedProfile: profile,
            expectedCheckpointPath: artifact.checkpointPath,
            requiresPolicyPass: true
        )
        Issue.record("Expected non-finite metric to throw.")
    } catch CheckpointEvaluationArtifactValidator.ValidationError.nonFiniteMetric(let metric) {
        #expect(metric == "policyScore")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func checkpointEvaluationArtifactValidatorRejectsTaskQualityMismatch() throws {
    let profile = try TaskEvaluationProfile.profile(task: "lift")
    let artifact = makeCheckpointEvaluationArtifact(
        profile: profile,
        qualitySummary: [makeTaskQualitySummary(task: "singleLift")]
    )

    do {
        try CheckpointEvaluationArtifactValidator.validate(
            artifact,
            expectedProfile: profile,
            expectedCheckpointPath: artifact.checkpointPath,
            requiresPolicyPass: true
        )
        Issue.record("Expected quality task mismatch to throw.")
    } catch CheckpointEvaluationArtifactValidator.ValidationError.qualityTaskMismatch(let expected, let actual) {
        #expect(expected == "lift")
        #expect(actual == "singleLift")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func checkpointEvaluationArtifactValidatorRejectsMissingLiftTaskQuality() throws {
    let profile = try TaskEvaluationProfile.profile(task: "lift")
    let artifact = makeCheckpointEvaluationArtifact(profile: profile, qualitySummary: [])

    do {
        try CheckpointEvaluationArtifactValidator.validate(
            artifact,
            expectedProfile: profile,
            expectedCheckpointPath: artifact.checkpointPath,
            requiresPolicyPass: true
        )
        Issue.record("Expected missing task quality to throw.")
    } catch CheckpointEvaluationArtifactValidator.ValidationError.missingTaskQuality(let task) {
        #expect(task == "lift")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func checkpointEvaluationArtifactValidatorRejectsMissingExpectedTaskQuality() throws {
    let profile = try TaskEvaluationProfile.profile(task: "lift")
    let artifact = makeCheckpointEvaluationArtifact(
        profile: profile,
        expectedQualityKeys: [
            CheckpointEvaluationScenarioKey(scenarioID: "lift-test", seed: 1),
            CheckpointEvaluationScenarioKey(scenarioID: "lift-test-2", seed: 2),
        ],
        qualitySummary: [makeTaskQualitySummary(task: "lift", scenarioID: "lift-test", seed: 1)]
    )

    do {
        try CheckpointEvaluationArtifactValidator.validate(
            artifact,
            expectedProfile: profile,
            expectedCheckpointPath: artifact.checkpointPath,
            requiresPolicyPass: true
        )
        Issue.record("Expected missing expected quality to throw.")
    } catch CheckpointEvaluationArtifactValidator.ValidationError.missingExpectedTaskQuality(let scenarioID, let seed) {
        #expect(scenarioID == "lift-test-2")
        #expect(seed == 2)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func checkpointEvaluationArtifactValidatorRejectsUnexpectedTaskQuality() throws {
    let profile = try TaskEvaluationProfile.profile(task: "lift")
    let artifact = makeCheckpointEvaluationArtifact(
        profile: profile,
        expectedQualityKeys: [CheckpointEvaluationScenarioKey(scenarioID: "lift-test", seed: 1)],
        qualitySummary: [
            makeTaskQualitySummary(task: "lift", scenarioID: "lift-test", seed: 1),
            makeTaskQualitySummary(task: "lift", scenarioID: "lift-extra", seed: 2),
        ]
    )

    do {
        try CheckpointEvaluationArtifactValidator.validate(
            artifact,
            expectedProfile: profile,
            expectedCheckpointPath: artifact.checkpointPath,
            requiresPolicyPass: true
        )
        Issue.record("Expected unexpected quality to throw.")
    } catch CheckpointEvaluationArtifactValidator.ValidationError.unexpectedTaskQuality(let scenarioID, let seed) {
        #expect(scenarioID == "lift-extra")
        #expect(seed == 2)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func checkpointEvaluationArtifactValidatorRejectsDuplicateExpectedTaskQuality() throws {
    let profile = try TaskEvaluationProfile.profile(task: "lift")
    let key = CheckpointEvaluationScenarioKey(scenarioID: "lift-test", seed: 1)
    let artifact = makeCheckpointEvaluationArtifact(
        profile: profile,
        expectedQualityKeys: [key, key]
    )

    do {
        try CheckpointEvaluationArtifactValidator.validate(
            artifact,
            expectedProfile: profile,
            expectedCheckpointPath: artifact.checkpointPath,
            requiresPolicyPass: true
        )
        Issue.record("Expected duplicate expected quality to throw.")
    } catch CheckpointEvaluationArtifactValidator.ValidationError.duplicateExpectedTaskQuality(let scenarioID, let seed) {
        #expect(scenarioID == "lift-test")
        #expect(seed == 1)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func checkpointEvaluationArtifactValidatorRejectsDuplicateTaskQualitySummary() throws {
    let profile = try TaskEvaluationProfile.profile(task: "lift")
    let artifact = makeCheckpointEvaluationArtifact(
        profile: profile,
        expectedQualityKeys: [CheckpointEvaluationScenarioKey(scenarioID: "lift-test", seed: 1)],
        qualitySummary: [
            makeTaskQualitySummary(task: "lift", scenarioID: "lift-test", seed: 1),
            makeTaskQualitySummary(task: "lift", scenarioID: "lift-test", seed: 1),
        ]
    )

    do {
        try CheckpointEvaluationArtifactValidator.validate(
            artifact,
            expectedProfile: profile,
            expectedCheckpointPath: artifact.checkpointPath,
            requiresPolicyPass: true
        )
        Issue.record("Expected duplicate quality summary to throw.")
    } catch CheckpointEvaluationArtifactValidator.ValidationError.duplicateTaskQuality(let scenarioID, let seed) {
        #expect(scenarioID == "lift-test")
        #expect(seed == 1)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func checkpointEvaluationArtifactValidatorRejectsDuplicateScenarioHorizon() throws {
    let profile = try TaskEvaluationProfile.profile(task: "lift")
    let key = CheckpointEvaluationScenarioKey(scenarioID: "lift-test", seed: 1)
    let horizon = CheckpointEvaluationScenarioHorizon(
        scenarioID: key.scenarioID,
        seed: key.seed,
        durationSeconds: 8,
        timeStepSeconds: 0.001,
        stepCount: 8000
    )
    let artifact = makeCheckpointEvaluationArtifact(
        profile: profile,
        expectedQualityKeys: [key],
        qualitySummary: [makeTaskQualitySummary(task: "lift", scenarioID: key.scenarioID, seed: key.seed)],
        scenarioHorizons: [horizon, horizon]
    )

    do {
        try CheckpointEvaluationArtifactValidator.validate(
            artifact,
            expectedProfile: profile,
            expectedCheckpointPath: artifact.checkpointPath,
            requiresPolicyPass: true
        )
        Issue.record("Expected duplicate scenario horizon to throw.")
    } catch CheckpointEvaluationArtifactValidator.ValidationError.duplicateScenarioHorizon(let scenarioID, let seed) {
        #expect(scenarioID == "lift-test")
        #expect(seed == 1)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func checkpointEvaluationArtifactValidatorRejectsInvalidScenarioHorizon() throws {
    let profile = try TaskEvaluationProfile.profile(task: "lift")
    let artifact = makeCheckpointEvaluationArtifact(
        profile: profile,
        expectedQualityKeys: [CheckpointEvaluationScenarioKey(scenarioID: "lift-test", seed: 1)],
        qualitySummary: [makeTaskQualitySummary(task: "lift", scenarioID: "lift-test", seed: 1)],
        scenarioHorizons: [
            CheckpointEvaluationScenarioHorizon(
                scenarioID: "lift-test",
                seed: 1,
                durationSeconds: 8,
                timeStepSeconds: 0.001,
                stepCount: 1
            )
        ]
    )

    do {
        try CheckpointEvaluationArtifactValidator.validate(
            artifact,
            expectedProfile: profile,
            expectedCheckpointPath: artifact.checkpointPath,
            requiresPolicyPass: true
        )
        Issue.record("Expected invalid scenario horizon to throw.")
    } catch CheckpointEvaluationArtifactValidator.ValidationError.invalidScenarioHorizon(let scenarioID, let seed) {
        #expect(scenarioID == "lift-test")
        #expect(seed == 1)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func checkpointEvaluationArtifactValidatorRejectsMissingScenarioHorizon() throws {
    let profile = try TaskEvaluationProfile.profile(task: "lift")
    let artifact = makeCheckpointEvaluationArtifact(
        profile: profile,
        expectedQualityKeys: [
            CheckpointEvaluationScenarioKey(scenarioID: "lift-test", seed: 1),
            CheckpointEvaluationScenarioKey(scenarioID: "lift-test-2", seed: 2),
        ],
        qualitySummary: [
            makeTaskQualitySummary(task: "lift", scenarioID: "lift-test", seed: 1),
            makeTaskQualitySummary(task: "lift", scenarioID: "lift-test-2", seed: 2),
        ],
        scenarioHorizons: [
            CheckpointEvaluationScenarioHorizon(
                scenarioID: "lift-test",
                seed: 1,
                durationSeconds: 8,
                timeStepSeconds: 0.001,
                stepCount: 8000
            )
        ]
    )

    do {
        try CheckpointEvaluationArtifactValidator.validate(
            artifact,
            expectedProfile: profile,
            expectedCheckpointPath: artifact.checkpointPath,
            requiresPolicyPass: true
        )
        Issue.record("Expected missing scenario horizon to throw.")
    } catch CheckpointEvaluationArtifactValidator.ValidationError.missingScenarioHorizon(let scenarioID, let seed) {
        #expect(scenarioID == "lift-test-2")
        #expect(seed == 2)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

private func makeCheckpointEvaluationArtifact(
    profile: TaskEvaluationProfile,
    schemaVersion: Int = CheckpointEvaluationArtifact.currentSchemaVersion,
    policyScore: Double = 1,
    expectedQualityKeys: [CheckpointEvaluationScenarioKey]? = nil,
    qualitySummary: [ReferenceQuadrotorTaskQualitySummary]? = nil,
    scenarioHorizons: [CheckpointEvaluationScenarioHorizon]? = nil
) -> CheckpointEvaluationArtifact {
    let summaries = qualitySummary ?? [makeTaskQualitySummary(task: profile.task)]
    let diagnostics: CheckpointEvaluationDiagnostics?
    if let first = summaries.first {
        diagnostics = CheckpointEvaluationDiagnostics(scenarioComparisons: [
            CheckpointEvaluationScenarioDiagnostics(
                key: CheckpointEvaluationScenarioKey(scenarioID: first.scenarioID, seed: first.seed),
                teacherLog: nil,
                policyLog: nil,
                altitudeDivergenceThreshold: 0.25
            )
        ])
    } else {
        diagnostics = nil
    }
    return CheckpointEvaluationArtifact(
        schemaVersion: schemaVersion,
        evaluationID: "eval-test",
        startedAt: Date(timeIntervalSince1970: 1),
        task: profile.task,
        profileID: profile.profileID,
        checkpointPath: "/tmp/checkpoint",
        teacherScore: 1,
        policyScore: policyScore,
        teacherPassed: true,
        policyPassed: true,
        failureReasons: [],
        expectedQualityKeys: expectedQualityKeys ?? summaries.map(CheckpointEvaluationScenarioKey.init(qualitySummary:)),
        qualitySummary: summaries,
        scenarioHorizons: scenarioHorizons,
        motorMAE: 0,
        driveMAE: 0,
        finalAltitudeDelta: 0,
        policyAverageMotorFinalOutputByIndex: [0, 0, 0, 0],
        teacherAverageMotorFinalOutputByIndex: [0, 0, 0, 0],
        diagnostics: diagnostics
    )
}

private func makeTaskQualitySummary(
    task: String,
    scenarioID: String? = nil,
    seed: UInt64 = 1
) -> ReferenceQuadrotorTaskQualitySummary {
    ReferenceQuadrotorTaskQualitySummary(
        task: task,
        scenarioID: scenarioID ?? "\(task)-test",
        seed: seed,
        passed: true,
        failureReasons: [],
        evaluatorID: "ReferenceQuadrotorTaskQualityEvaluator",
        targetZ: 1,
        tolerance: 0.1,
        warmupTime: 0,
        requiredHoldTime: 1,
        achievedHoldTime: 1,
        maxAltitudeErrorAfterWarmup: 0,
        maxVerticalVelocityAfterWarmup: 0
    )
}
