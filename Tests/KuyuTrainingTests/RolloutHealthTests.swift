import Foundation
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

    let reasons = RolloutHealthAcceptancePolicy.rootRigidBodyConservative
        .rejectionReasons(candidate: candidate, relativeTo: baseline)

    #expect(reasons == [.omegaRegressed])
    #expect(!candidate.isAcceptable(
        relativeTo: baseline,
        policy: .rootRigidBodyConservative
    ))
}

@Test func genericRolloutHealthAcceptanceDoesNotAssumeRootRigidBodyMetrics() throws {
    let baseline = RolloutHealth(episodes: [
        try makeRolloutHealthEpisode(rewardSum: 1.0, omega: 1.0, tilt: 0.1, altitude: 2.0),
    ])
    let candidate = RolloutHealth(episodes: [
        try makeRolloutHealthEpisode(rewardSum: 1.0, omega: 2.0, tilt: 0.1, altitude: 2.0),
    ])

    let reasons = RolloutHealthAcceptancePolicy.conservative
        .rejectionReasons(candidate: candidate, relativeTo: baseline)

    #expect(reasons.isEmpty)
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

@Test func rolloutHealthTracksTerminalStepProgress() throws {
    let health = RolloutHealth(episodes: [
        try makeRolloutHealthEpisode(
            rewardSum: -1.0,
            omega: 0.5,
            tilt: 0.05,
            altitude: 1.8,
            failureReason: "sustained-fall",
            stepCount: 5_000
        ),
        try makeRolloutHealthEpisode(
            rewardSum: 1.0,
            omega: 0.5,
            tilt: 0.05,
            altitude: 2.0,
            terminalReason: RolloutTerminalReason.curriculumHorizon,
            stepCount: 20_000
        ),
    ])

    #expect(health.terminalStepObservationCount == 2)
    #expect(health.terminalStepSum == 25_000)
    #expect(health.terminalStepAverage == 12_500)
    #expect(health.failureReasonCounts == ["sustained-fall": 1])
    #expect(health.failureReasonCount("sustained-fall") == 1)
    #expect(health.containsFailureReason(in: ["sustained-fall"]))
}

@Test func rolloutHealthAggregatesFailureReasonCounts() throws {
    var health = RolloutHealth(episodes: [
        try makeRolloutHealthEpisode(
            rewardSum: -1.0,
            omega: 0.5,
            tilt: 0.05,
            altitude: 1.8,
            failureReason: "sustained-fall"
        ),
        try makeRolloutHealthEpisode(
            rewardSum: -1.0,
            omega: 0.5,
            tilt: 0.05,
            altitude: 0.0,
            failureReason: "ground-violation"
        ),
    ])
    health.addEpisodeSummary(
        done: true,
        truncated: false,
        failureReason: " sustained-fall ",
        terminalReason: "sustained-fall",
        rewardSum: -1.0,
        maxOmega: 0.5,
        maxTilt: 0.05,
        minAltitude: 1.8
    )

    #expect(health.failureCount == 3)
    #expect(health.failureReasonCounts == [
        "ground-violation": 1,
        "sustained-fall": 2,
    ])
    #expect(health.failureReasonCount(" sustained-fall ") == 2)
    #expect(health.containsFailureReason(in: ["ground-violation"]))
    #expect(!health.containsFailureReason(in: ["safety-envelope"]))
}

@Test func rolloutHealthMatchesFailureReasonFragments() {
    var health = RolloutHealth()
    health.addEpisodeSummary(
        done: true,
        truncated: false,
        failureReason: "task:ground-violation",
        terminalReason: "ground-violation",
        rewardSum: -1.0,
        maxOmega: 0.5,
        maxTilt: 0.05,
        minAltitude: 0.0
    )

    #expect(health.failureReasonCount("ground-violation") == 0)
    #expect(!health.containsFailureReason(in: ["ground-violation"]))
    #expect(health.containsFailureReason(matching: ["ground-violation"]))
    #expect(!health.containsFailureReason(matching: ["sustained-fall"]))
}

@Test func rolloutHealthDecodesLegacyPayloadWithoutTerminalStepProgress() throws {
    let legacyJSON = """
    {
      "cancelledCount" : 0,
      "doneCount" : 0,
      "episodeCount" : 1,
      "failureCount" : 0,
      "horizonLimitCount" : 1,
      "maxOmega" : 0.5,
      "maxTilt" : 0.05,
      "minAltitude" : 2.0,
      "nonFiniteMetricCount" : 0,
      "rewardSum" : 1.0,
      "stabilityMetricContractViolations" : [],
      "stabilityMetrics" : {},
      "truncatedCount" : 1
    }
    """.data(using: .utf8)!

    let health = try JSONDecoder().decode(RolloutHealth.self, from: legacyJSON)

    #expect(health.terminalStepObservationCount == 0)
    #expect(health.terminalStepSum == 0)
    #expect(health.terminalStepAverage == 0)
    #expect(health.failureReasonCounts.isEmpty)
}

@Test func rolloutHealthDecodeRejectsNegativeFailureReasonCount() throws {
    let payload = rolloutHealthPayload(
        failureCount: 1,
        failureReasonCountsJSON: "\"ground-violation\" : -1"
    )

    #expect(
        throws: RolloutHealth.ValidationError.invalidFailureReasonCount(
            reason: "ground-violation",
            count: -1
        )
    ) {
        _ = try JSONDecoder().decode(RolloutHealth.self, from: payload)
    }
}

@Test func rolloutHealthDecodeRejectsEmptyFailureReason() throws {
    let payload = rolloutHealthPayload(
        failureCount: 1,
        failureReasonCountsJSON: "\" \" : 1"
    )

    #expect(throws: RolloutHealth.ValidationError.invalidFailureReason(" ")) {
        _ = try JSONDecoder().decode(RolloutHealth.self, from: payload)
    }
}

@Test func rolloutHealthDecodeRejectsFailureReasonCountMismatch() throws {
    let payload = rolloutHealthPayload(
        failureCount: 2,
        failureReasonCountsJSON: "\"ground-violation\" : 1"
    )

    #expect(
        throws: RolloutHealth.ValidationError.failureReasonCountMismatch(
            expected: 2,
            actual: 1
        )
    ) {
        _ = try JSONDecoder().decode(RolloutHealth.self, from: payload)
    }
}

private func rolloutHealthPayload(
    failureCount: Int,
    failureReasonCountsJSON: String
) -> Data {
    Data("""
    {
      "cancelledCount" : 0,
      "doneCount" : \(failureCount),
      "episodeCount" : 2,
      "failureCount" : \(failureCount),
      "failureReasonCounts" : { \(failureReasonCountsJSON) },
      "horizonLimitCount" : 0,
      "maxOmega" : 0.5,
      "maxTilt" : 0.05,
      "minAltitude" : 1.0,
      "nonFiniteMetricCount" : 0,
      "rewardSum" : 0.0,
      "stabilityMetricContractViolations" : [],
      "stabilityMetrics" : {},
      "terminalStepObservationCount" : 2,
      "terminalStepSum" : 2,
      "truncatedCount" : 0
    }
    """.utf8)
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
        minAltitude: 1.5,
        terminalStepCount: 2_000
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
        terminalStepCount: 100,
        nonFiniteMetricCount: 1
    )

    baseline.add(candidate)

    #expect(baseline.episodeCount == 2)
    #expect(baseline.doneCount == 1)
    #expect(baseline.truncatedCount == 1)
    #expect(baseline.failureCount == 1)
    #expect(baseline.horizonLimitCount == 1)
    #expect(baseline.terminalStepObservationCount == 2)
    #expect(baseline.terminalStepSum == 2_100)
    #expect(baseline.nonHorizonTruncationCount == 0)
    #expect(baseline.rewardSum == 2.0)
    #expect(baseline.maxOmega == 1.2)
    #expect(baseline.maxTilt == 0.08)
    #expect(baseline.minAltitude == 1.5)
    #expect(baseline.nonFiniteMetricCount == 4)
    #expect(baseline.failureReasonCounts == ["ground-violation": 1])
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
        RolloutHealthAcceptancePolicy.rootRigidBodyConservative
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

    let reasons = RolloutHealthAcceptancePolicy.rootRigidBodyConservative
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

    let reasons = RolloutHealthAcceptancePolicy.rootRigidBodyConservative
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

    let reasons = RolloutHealthAcceptancePolicy.rootRigidBodyConservative
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

    let reasons = RolloutHealthAcceptancePolicy.rootRigidBodyConservative
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

    let reasons = RolloutHealthAcceptancePolicy.rootRigidBodyConservative
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

@Test func rolloutStabilityRegressionEnvelopeDetectsProfileDefinedImprovement() throws {
    var baseline = RolloutHealth()
    baseline.recordStabilityMetric(id: "joint.maximumVelocity", value: 0.7, aggregation: .maximum)
    baseline.recordStabilityMetric(id: "root.clearance", value: 0.2, aggregation: .minimum)
    var candidate = RolloutHealth()
    candidate.recordStabilityMetric(id: "joint.maximumVelocity", value: 0.4, aggregation: .maximum)
    candidate.recordStabilityMetric(id: "root.clearance", value: 0.3, aggregation: .minimum)
    let envelope = try RolloutStabilityRegressionEnvelope(checks: [
        try RolloutStabilityRegressionCheck(
            metricID: "joint.maximumVelocity",
            direction: .upperBound,
            absoluteTolerance: 0.1,
            relativeTolerance: 0.25,
            rejectionReason: .stabilityMetricRegressed
        ),
        try RolloutStabilityRegressionCheck(
            metricID: "root.clearance",
            direction: .lowerBound,
            absoluteTolerance: 0.05,
            relativeTolerance: 0.0,
            rejectionReason: .stabilityMetricRegressed
        ),
    ])

    #expect(envelope.hasDirectionalImprovement(candidate: candidate, relativeTo: baseline))
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

@Test func rolloutStabilityLimitEnvelopeUsesProfileDefinedUpperLimit() throws {
    var health = RolloutHealth()
    health.recordStabilityMetric(id: "joint.maximumVelocity", value: 0.7, aggregation: .maximum)
    let envelope = try RolloutStabilityLimitEnvelope(checks: [
        try RolloutStabilityLimitCheck(
            metricID: "joint.maximumVelocity",
            direction: .upperBound,
            limit: 0.5,
            rejectionReason: .stabilityMetricRegressed
        ),
    ])

    let reasons = envelope.rejectionReasons(health: health)

    #expect(reasons == [.stabilityMetricRegressed])
}

@Test func rolloutStabilityLimitEnvelopeUsesProfileDefinedLowerLimit() throws {
    var health = RolloutHealth()
    health.recordStabilityMetric(id: "root.clearance", value: 0.2, aggregation: .minimum)
    let envelope = try RolloutStabilityLimitEnvelope(checks: [
        try RolloutStabilityLimitCheck(
            metricID: "root.clearance",
            direction: .lowerBound,
            limit: 0.3,
            rejectionReason: .stabilityMetricRegressed
        ),
    ])

    let reasons = envelope.rejectionReasons(health: health)

    #expect(reasons == [.stabilityMetricRegressed])
}

@Test func rolloutStabilityLimitEnvelopeRejectsMissingConfiguredMetric() throws {
    let health = RolloutHealth()
    let envelope = try RolloutStabilityLimitEnvelope(checks: [
        try RolloutStabilityLimitCheck(
            metricID: "joint.maximumVelocity",
            direction: .upperBound,
            limit: 0.5,
            rejectionReason: .stabilityMetricRegressed
        ),
    ])

    let reasons = envelope.rejectionReasons(health: health)

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
    cancelled: Bool = false,
    stepCount: Int = 1
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
        stepCount: max(0, stepCount),
        durationSeconds: time.time,
        cancelled: cancelled,
        steps: [step]
    )
}
