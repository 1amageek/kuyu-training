import Testing
@testable import KuyuTraining

@Test func rolloutHealthProgressRequiresMaterialImprovementAfterRetention() throws {
    let baseline = progressHealth(rewards: [1, 1])
    let candidate = progressHealth(rewards: [1.001, 1.001])
    let policy = try RolloutHealthProgressPolicy(
        minimumEpisodeCount: 2,
        minimumRewardAverageImprovement: 0.01
    )

    let assessment = policy.assessment(
        candidate: candidate,
        relativeTo: baseline,
        retentionRejectionReasons: [],
        stabilityRegressionEnvelope: .empty
    )

    #expect(!assessment.qualified)
    #expect(assessment.progressSignals.isEmpty)
    #expect(assessment.progressRejectionReasons == [.noMaterialImprovement])
}

@Test func rolloutHealthProgressQualifiesReducedFailures() throws {
    let baseline = progressHealth(rewards: [0, 1], failedIndices: [0])
    let candidate = progressHealth(rewards: [0, 1])
    let policy = try RolloutHealthProgressPolicy(minimumEpisodeCount: 2)

    let assessment = policy.assessment(
        candidate: candidate,
        relativeTo: baseline,
        retentionRejectionReasons: [],
        stabilityRegressionEnvelope: .empty
    )

    #expect(assessment.qualified)
    #expect(assessment.failureCountDelta == -1)
    #expect(assessment.progressSignals == [.failureCountReduced])
}

@Test func rolloutHealthProgressRejectsImprovedCandidateWhenRetentionFailed() throws {
    let baseline = progressHealth(rewards: [0, 0])
    let candidate = progressHealth(rewards: [1, 1])
    let policy = try RolloutHealthProgressPolicy(minimumEpisodeCount: 2)

    let assessment = policy.assessment(
        candidate: candidate,
        relativeTo: baseline,
        retentionRejectionReasons: [.omegaRegressed],
        stabilityRegressionEnvelope: .empty
    )

    #expect(!assessment.qualified)
    #expect(assessment.progressSignals == [.rewardAverageImproved])
    #expect(assessment.progressRejectionReasons == [.candidateNotRetained])
}

@Test func rolloutHealthProgressReportsMaterialStabilityMetricIdentity() throws {
    var baseline = progressHealth(rewards: [1])
    baseline.recordStabilityMetric(
        id: .maximumAngularRate,
        value: 2,
        aggregation: .maximum
    )
    var candidate = progressHealth(rewards: [1])
    candidate.recordStabilityMetric(
        id: .maximumAngularRate,
        value: 1,
        aggregation: .maximum
    )
    let check = try RolloutStabilityRegressionCheck(
        metricID: .maximumAngularRate,
        direction: .upperBound,
        absoluteTolerance: 0.1,
        relativeTolerance: 0,
        rejectionReason: .omegaRegressed
    )
    let policy = try RolloutHealthProgressPolicy(minimumEpisodeCount: 1)

    let assessment = policy.assessment(
        candidate: candidate,
        relativeTo: baseline,
        retentionRejectionReasons: [],
        stabilityRegressionEnvelope: try .init(checks: [check])
    )

    #expect(assessment.qualified)
    #expect(assessment.progressSignals == [
        .stabilityMetricImproved(.maximumAngularRate),
    ])
}

private func progressHealth(
    rewards: [Double],
    failedIndices: Set<Int> = []
) -> RolloutHealth {
    var health = RolloutHealth()
    for (index, reward) in rewards.enumerated() {
        health.addEpisodeSummary(
            done: true,
            truncated: false,
            failureReason: failedIndices.contains(index) ? "progress-test-failure" : nil,
            terminalReason: "done",
            rewardSum: reward,
            maxOmega: 0,
            maxTilt: 0,
            minAltitude: 1,
            terminalStepCount: 1
        )
    }
    return health
}
