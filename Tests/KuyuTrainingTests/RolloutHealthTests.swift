import Testing
import KuyuCore
import KuyuPhysics
@testable import KuyuTraining

@Test func rolloutHealthRejectsSameFailureCountWithWorseInstability() throws {
    let baseline = RolloutHealth(episodes: [
        try makeRolloutHealthEpisode(rewardSum: 1.0, omega: 1.0, tilt: 0.1, altitude: 2.0),
    ])
    let candidate = RolloutHealth(episodes: [
        try makeRolloutHealthEpisode(rewardSum: 1.0, omega: 2.0, tilt: 0.1, altitude: 2.0),
    ])

    let reasons = RolloutHealthAcceptancePolicy.conservative
        .rejectionReasons(candidate: candidate, relativeTo: baseline)

    #expect(reasons == [.omegaRegressed])
    #expect(!candidate.isAcceptable(relativeTo: baseline))
}

@Test func rolloutHealthCountsHorizonLimitAsTerminalHealthSignal() throws {
    let health = RolloutHealth(episodes: [
        try makeRolloutHealthEpisode(
            rewardSum: 1.0,
            omega: 0.5,
            tilt: 0.05,
            altitude: 2.0,
            terminalReason: RolloutTerminalReason.curriculumHorizon
        ),
    ])

    #expect(health.failureCount == 0)
    #expect(health.truncatedCount == 1)
    #expect(health.horizonLimitCount == 1)
    #expect(health.nonHorizonTruncationCount == 0)
    #expect(health.failureRate == 0)
}

@Test func rolloutHealthCountsTimeLimitAsHorizonLimit() throws {
    let health = RolloutHealth(episodes: [
        try makeRolloutHealthEpisode(
            rewardSum: 1.0,
            omega: 0.5,
            tilt: 0.05,
            altitude: 2.0,
            terminalReason: RolloutTerminalReason.timeLimit
        ),
    ])

    #expect(health.failureCount == 0)
    #expect(health.truncatedCount == 1)
    #expect(health.horizonLimitCount == 1)
    #expect(health.nonHorizonTruncationCount == 0)
}

@Test func rolloutHealthAddsSummariesAndMergesWithoutEpisodes() {
    var baseline = RolloutHealth()
    baseline.addEpisodeSummary(
        done: false,
        truncated: true,
        failureReason: nil,
        terminalReason: RolloutTerminalReason.curriculumHorizon,
        rewardSum: 2.0,
        maxOmega: 0.7,
        maxTilt: 0.08,
        minAltitude: 1.5
    )

    var candidate = RolloutHealth()
    candidate.addEpisodeSummary(
        done: true,
        truncated: false,
        failureReason: "ground-violation",
        terminalReason: "ground-violation",
        rewardSum: .infinity,
        maxOmega: 1.2,
        maxTilt: .nan,
        minAltitude: .infinity,
        nonFiniteMetricCount: 1
    )

    baseline.add(candidate)

    #expect(baseline.episodeCount == 2)
    #expect(baseline.doneCount == 1)
    #expect(baseline.truncatedCount == 1)
    #expect(baseline.failureCount == 1)
    #expect(baseline.horizonLimitCount == 1)
    #expect(baseline.nonHorizonTruncationCount == 0)
    #expect(baseline.rewardSum == 2.0)
    #expect(baseline.maxOmega == 1.2)
    #expect(baseline.maxTilt == 0.08)
    #expect(baseline.minAltitude == 1.5)
    #expect(baseline.nonFiniteMetricCount == 4)
}

@Test func rolloutHealthRejectsNewCancellationAndNonHorizonTruncation() throws {
    let baseline = RolloutHealth(episodes: [
        try makeRolloutHealthEpisode(rewardSum: 1.0, omega: 0.5, tilt: 0.05, altitude: 2.0),
    ])
    let candidate = RolloutHealth(episodes: [
        try makeRolloutHealthEpisode(
            rewardSum: 1.0,
            omega: 0.5,
            tilt: 0.05,
            altitude: 2.0,
            terminalReason: "max-steps",
            cancelled: true
        ),
    ])

    let reasons = Set(
        RolloutHealthAcceptancePolicy.conservative
            .rejectionReasons(candidate: candidate, relativeTo: baseline)
    )

    #expect(reasons.contains(.cancellationCountRegressed))
    #expect(reasons.contains(.nonHorizonTruncationRegressed))
}

@Test func rolloutHealthRejectsNonFiniteMetrics() throws {
    let baseline = RolloutHealth(episodes: [
        try makeRolloutHealthEpisode(rewardSum: 1.0, omega: 0.5, tilt: 0.05, altitude: 2.0),
    ])
    let candidate = RolloutHealth(episodes: [
        try makeRolloutHealthEpisode(rewardSum: .infinity, omega: 0.5, tilt: 0.05, altitude: 2.0),
    ])

    let reasons = RolloutHealthAcceptancePolicy.conservative
        .rejectionReasons(candidate: candidate, relativeTo: baseline)

    #expect(reasons.contains(.nonFiniteMetric))
}

@Test func rolloutHealthRejectsNonFiniteBaselineMetrics() throws {
    let baseline = RolloutHealth(episodes: [
        try makeRolloutHealthEpisode(rewardSum: .infinity, omega: 0.5, tilt: 0.05, altitude: 2.0),
    ])
    let candidate = RolloutHealth(episodes: [
        try makeRolloutHealthEpisode(rewardSum: 1.0, omega: 0.5, tilt: 0.05, altitude: 2.0),
    ])

    let reasons = RolloutHealthAcceptancePolicy.conservative
        .rejectionReasons(candidate: candidate, relativeTo: baseline)

    #expect(!baseline.isValidForTrainingDecision)
    #expect(reasons.contains(.nonFiniteMetric))
}

@Test func rolloutHealthMirrorsBuiltInStabilityMetrics() throws {
    let health = RolloutHealth(episodes: [
        try makeRolloutHealthEpisode(rewardSum: 1.0, omega: 0.7, tilt: 0.08, altitude: 2.0),
        try makeRolloutHealthEpisode(rewardSum: 1.0, omega: 1.1, tilt: 0.05, altitude: 1.7),
    ])

    #expect(health.maxOmega == 1.1)
    #expect(health.maxTilt == 0.08)
    #expect(health.minAltitude == 1.7)
    #expect(health.stabilityMetricValue(.maximumAngularRate) == 1.1)
    #expect(health.stabilityMetricValue(.maximumAttitudeDeviation) == 0.08)
    #expect(health.stabilityMetricValue(.minimumRootAltitude) == 1.7)
}

@Test func rolloutHealthAggregatesProfileDefinedStabilityMetrics() {
    var health = RolloutHealth()
    health.recordStabilityMetric(id: "joint.maximumVelocity", value: 0.4, aggregation: .maximum)
    health.recordStabilityMetric(id: "joint.maximumVelocity", value: 0.9, aggregation: .maximum)
    health.recordStabilityMetric(id: "root.clearance", value: 0.3, aggregation: .minimum)
    health.recordStabilityMetric(id: "root.clearance", value: 0.2, aggregation: .minimum)

    #expect(health.stabilityMetricValue("joint.maximumVelocity") == 0.9)
    #expect(health.stabilityMetricValue("root.clearance") == 0.2)
}

@Test func rolloutHealthCountsNonFiniteProfileMetric() {
    var health = RolloutHealth()
    health.recordStabilityMetric(id: "joint.maximumVelocity", value: .infinity, aggregation: .maximum)

    #expect(health.stabilityMetricValue("joint.maximumVelocity") == nil)
    #expect(health.nonFiniteMetricCount == 1)
}

@Test func rolloutHealthRejectsProfileMetricAggregationMismatch() {
    var health = RolloutHealth()
    health.recordStabilityMetric(id: "joint.maximumVelocity", value: 0.4, aggregation: .maximum)
    health.recordStabilityMetric(id: "joint.maximumVelocity", value: 0.1, aggregation: .minimum)

    let reasons = RolloutHealthAcceptancePolicy.conservative
        .rejectionReasons(candidate: health, relativeTo: RolloutHealth())

    #expect(health.stabilityMetricValue("joint.maximumVelocity") == 0.4)
    #expect(health.stabilityMetricContractViolations == [
        RolloutStabilityMetricContractViolation(
            metricID: "joint.maximumVelocity",
            reason: .aggregationMismatch
        ),
    ])
    #expect(reasons.contains(.stabilityMetricContractViolation))
}

@Test func rolloutHealthRejectsEmptyProfileMetricID() {
    var health = RolloutHealth()
    health.recordStabilityMetric(id: " ", value: 0.4, aggregation: .maximum)

    let reasons = RolloutHealthAcceptancePolicy.conservative
        .rejectionReasons(candidate: health, relativeTo: RolloutHealth())

    #expect(health.stabilityMetricContractViolations == [
        RolloutStabilityMetricContractViolation(metricID: " ", reason: .emptyMetricID),
    ])
    #expect(reasons.contains(.stabilityMetricContractViolation))
}

@Test func rolloutHealthRejectsInvalidBaselineStabilityMetricContract() {
    var baseline = RolloutHealth()
    baseline.recordStabilityMetric(id: "joint.maximumVelocity", value: 0.4, aggregation: .maximum)
    baseline.recordStabilityMetric(id: "joint.maximumVelocity", value: 0.1, aggregation: .minimum)
    var candidate = RolloutHealth()
    candidate.recordStabilityMetric(id: "joint.maximumVelocity", value: 0.4, aggregation: .maximum)

    let reasons = RolloutHealthAcceptancePolicy.conservative
        .rejectionReasons(candidate: candidate, relativeTo: baseline)

    #expect(reasons.contains(.stabilityMetricContractViolation))
}

@Test func rolloutStabilityRegressionEnvelopeUsesProfileDefinedMetric() throws {
    var baseline = RolloutHealth()
    baseline.recordStabilityMetric(id: "joint.maximumVelocity", value: 0.2, aggregation: .maximum)
    var candidate = RolloutHealth()
    candidate.recordStabilityMetric(id: "joint.maximumVelocity", value: 0.7, aggregation: .maximum)
    let envelope = try RolloutStabilityRegressionEnvelope(checks: [
        try RolloutStabilityRegressionCheck(
            metricID: "joint.maximumVelocity",
            direction: .upperBound,
            absoluteTolerance: 0.1,
            relativeTolerance: 0.25,
            rejectionReason: .stabilityMetricRegressed
        ),
    ])

    let reasons = envelope.rejectionReasons(candidate: candidate, relativeTo: baseline)

    #expect(reasons == [.stabilityMetricRegressed])
}

@Test func rolloutStabilityRegressionEnvelopeRejectsMissingConfiguredMetric() throws {
    var baseline = RolloutHealth()
    baseline.recordStabilityMetric(id: "joint.maximumVelocity", value: 0.2, aggregation: .maximum)
    let candidate = RolloutHealth()
    let envelope = try RolloutStabilityRegressionEnvelope(checks: [
        try RolloutStabilityRegressionCheck(
            metricID: "joint.maximumVelocity",
            direction: .upperBound,
            absoluteTolerance: 0.1,
            relativeTolerance: 0.25,
            rejectionReason: .stabilityMetricRegressed
        ),
    ])

    let reasons = envelope.rejectionReasons(candidate: candidate, relativeTo: baseline)

    #expect(reasons == [.stabilityMetricMissing])
}

@Test func rolloutStabilityRegressionCheckRejectsInvalidContract() {
    #expect(throws: RolloutStabilityRegressionContractError.emptyMetricID) {
        _ = try RolloutStabilityRegressionCheck(
            metricID: " ",
            direction: .upperBound,
            absoluteTolerance: 0.1,
            relativeTolerance: 0.25,
            rejectionReason: .stabilityMetricRegressed
        )
    }
    #expect(throws: RolloutStabilityRegressionContractError.invalidTolerance) {
        _ = try RolloutStabilityRegressionCheck(
            metricID: "joint.maximumVelocity",
            direction: .upperBound,
            absoluteTolerance: .nan,
            relativeTolerance: 0.25,
            rejectionReason: .stabilityMetricRegressed
        )
    }
}

@Test func rolloutStabilityRegressionEnvelopeRejectsDuplicateMetricChecks() throws {
    let first = try RolloutStabilityRegressionCheck(
        metricID: "joint.maximumVelocity",
        direction: .upperBound,
        absoluteTolerance: 0.1,
        relativeTolerance: 0.25,
        rejectionReason: .stabilityMetricRegressed
    )
    let second = try RolloutStabilityRegressionCheck(
        metricID: "joint.maximumVelocity",
        direction: .upperBound,
        absoluteTolerance: 0.2,
        relativeTolerance: 0.25,
        rejectionReason: .stabilityMetricRegressed
    )

    #expect(throws: RolloutStabilityRegressionContractError.duplicateMetricID("joint.maximumVelocity")) {
        _ = try RolloutStabilityRegressionEnvelope(checks: [first, second])
    }
}

private func makeRolloutHealthEpisode(
    rewardSum: Double,
    omega: Double,
    tilt: Double,
    altitude: Double,
    terminalReason: String? = nil,
    failureReason: String? = nil,
    cancelled: Bool = false
) throws -> RolloutEpisode {
    let time = try WorldTime(stepIndex: 1, time: 0.001)
    let root = RigidBodySnapshot(
        id: "root",
        position: Axis3(x: 0, y: 0, z: altitude),
        velocity: Axis3(x: 0, y: 0, z: 0),
        orientation: QuaternionSnapshot(w: 1, x: 0, y: 0, z: 0),
        angularVelocity: Axis3(x: omega, y: 0, z: 0)
    )
    let plantState = PlantStateSnapshot(root: root)
    let safetyTrace = try SafetyTrace(omegaMagnitude: omega, tiltRadians: tilt)
    let actuatorTelemetry = ActuatorTelemetrySnapshot(channels: [])
    let disturbances = DisturbanceSnapshot(
        forceWorld: Axis3(x: 0, y: 0, z: 0),
        torqueBody: Axis3(x: 0, y: 0, z: 0)
    )
    let log = WorldStepLog(
        time: time,
        events: [],
        sensorSamples: [],
        driveIntents: [],
        reflexCorrections: [],
        actuatorValues: [],
        actuatorTelemetry: actuatorTelemetry,
        safetyTrace: safetyTrace,
        plantState: plantState,
        disturbances: disturbances
    )
    let info = EpisodeInfo(
        scenarioId: try ScenarioID("ROLLOUT-HEALTH"),
        seed: ScenarioSeed(1),
        configHash: "health",
        stepCount: 1,
        rewardSum: rewardSum,
        terminalReason: terminalReason
    )
    let done = failureReason != nil
    let truncated = terminalReason != nil && !done
    let stepReward = rewardSum.isFinite ? rewardSum : 0
    let step = try EnvironmentStep(
        observation: EnvironmentObservation(log: log),
        reward: stepReward,
        done: done,
        truncated: truncated,
        info: info,
        log: log
    )
    return RolloutEpisode(
        episodeId: "health",
        scenarioId: "ROLLOUT-HEALTH",
        seed: 1,
        workerIndex: 0,
        policyId: "health",
        configHash: "health",
        robotManifestID: nil,
        rewardSum: rewardSum,
        done: done,
        truncated: truncated,
        terminalReason: terminalReason,
        failureReason: failureReason,
        failureTime: done ? time.time : nil,
        stepCount: 1,
        durationSeconds: time.time,
        cancelled: cancelled,
        steps: [step]
    )
}
