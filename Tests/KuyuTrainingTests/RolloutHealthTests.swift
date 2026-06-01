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
