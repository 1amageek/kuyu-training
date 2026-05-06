import Testing
import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
@testable import KuyuTraining

@Test func defaultWorkerCountLeavesOneProcessorAvailable() {
    #expect(ParallelRolloutCollector.defaultWorkerCount(activeProcessorCount: 1) == 1)
    #expect(ParallelRolloutCollector.defaultWorkerCount(activeProcessorCount: 2) == 1)
    #expect(ParallelRolloutCollector.defaultWorkerCount(activeProcessorCount: 8) == 4)
}

@Test func policySnapshotCarriesWorkerLocalModelIdentity() {
    let snapshot = PolicySnapshot(
        policyId: "manasMLX",
        snapshotId: "snapshot-a",
        modelDescriptorId: "robot-a",
        modelPath: "/tmp/model",
        configHash: "hash-a"
    )

    #expect(snapshot.policyId == "manasMLX")
    #expect(snapshot.snapshotId == "snapshot-a")
    #expect(snapshot.modelDescriptorId == "robot-a")
    #expect(snapshot.configHash == "hash-a")
}

@Test func serialAndParallelRolloutsProduceDeterministicRewardSummary() async throws {
    let definitions = try [
        makeShortAttitudeScenario(id: "KUY-RL-TRAIN/1", seed: 101),
        makeShortAttitudeScenario(id: "KUY-RL-TRAIN/2", seed: 102),
    ]
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: 1)
    let gains = try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2)
    let runner = RolloutRunner(
        schedule: schedule,
        determinism: .tier1Baseline,
        motorNerveRateLimitPerSecond: 100.0,
        motorNerveSmoothingTimeConstant: nil
    )
    let factory = KuyAtt1BaselinePolicyFactory(gains: gains, mode: .teacher)

    let serial = try await runner.run(definitions: definitions, policyFactory: factory, workerIndex: 0)
    let parallel = try await ParallelRolloutCollector(runner: runner, workerCount: 2)
        .collect(definitions: definitions, policyFactory: factory)

    #expect(serial.count == parallel.count)
    #expect(serial.map(\.scenarioId).sorted() == parallel.map(\.scenarioId))
    #expect(abs(RolloutSummary(episodes: serial).rewardSum - RolloutSummary(episodes: parallel).rewardSum) < 1e-9)
    #expect(parallel.allSatisfy { $0.truncated && !$0.done && $0.failureReason == nil })
}

@Test func parallelRolloutCollectorLimitsActiveWorkersToWorkerCount() async throws {
    let definitions = try (0..<6).map { index in
        try makeShortAttitudeScenario(id: "KUY-RL-WORKER-LIMIT/\(index)", seed: UInt64(500 + index))
    }
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: 1)
    let runner = RolloutRunner(
        schedule: schedule,
        determinism: .tier1Baseline,
        motorNerveRateLimitPerSecond: 100.0,
        motorNerveSmoothingTimeConstant: nil
    )
    let probe = WorkerConcurrencyProbe()
    let factory = SlowProbePolicyFactory(probe: probe)

    let episodes = try await ParallelRolloutCollector(runner: runner, workerCount: 2)
        .collect(definitions: definitions, policyFactory: factory)

    #expect(episodes.count == definitions.count)
    #expect(await probe.maximumActiveCount() <= 2)
    #expect(Set(episodes.map(\.workerIndex)) == Set([0, 1]))
    #expect(episodes.allSatisfy { $0.workerCount == 2 })
}

@Test func rolloutDatasetWriterIncludesRewardAndEpisodeMetadata() async throws {
    let definition = try makeShortAttitudeScenario(id: "KUY-RL-DATASET/1", seed: 201)
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: 1)
    let gains = try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2)
    let runner = RolloutRunner(
        schedule: schedule,
        determinism: .tier1Baseline,
        motorNerveRateLimitPerSecond: 100.0,
        motorNerveSmoothingTimeConstant: nil
    )
    let factory = KuyAtt1BaselinePolicyFactory(gains: gains, mode: .teacher)
    let episode = try await runner.runEpisode(definition: definition, policyFactory: factory)

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-rollout-writer-\(UUID().uuidString)", isDirectory: true)
    _ = try TrainingDatasetWriter().write(
        episode: episode,
        timeStep: definition.config.timeStep.delta,
        determinismTier: "tier1",
        to: root
    )

    let metaURL = root.appendingPathComponent("meta.json")
    let recordsURL = root.appendingPathComponent("records.jsonl")
    let meta = try JSONDecoder().decode(
        TrainingDatasetMetadata.self,
        from: Data(contentsOf: metaURL)
    )
    let lines = try String(contentsOf: recordsURL, encoding: .utf8)
        .split(separator: "\n")
    let firstLine = lines.first
    let recordData = Data(String(firstLine ?? "").utf8)
    let record = try JSONDecoder().decode(TrainingDatasetRecord.self, from: recordData)
    let records = try lines.map { line in
        try JSONDecoder().decode(TrainingDatasetRecord.self, from: Data(String(line).utf8))
    }

    #expect(meta.episodeId == episode.episodeId)
    #expect(meta.schemaVersion == TrainingDatasetMetadata.currentSchemaVersion)
    #expect(meta.policyId == "teacherBaseline")
    #expect(meta.rewardSum == episode.rewardSum)
    #expect(meta.rewardDescriptor == episode.rewardDescriptor)
    #expect(record.reward != nil)
    #expect(record.episodeId == episode.episodeId)
    #expect(record.physicsState?.count == 13)
    #expect(record.actualState?.count == 13)
    #expect(record.actionValues?.isEmpty == false)
    #expect(record.continueValue == 0.0 || record.continueValue == 1.0)
    #expect(records.dropFirst().contains { record in
        guard let physics = record.physicsState, let actual = record.actualState else { return false }
        return zip(physics, actual).contains { abs($0 - $1) > 1e-12 }
    })
}

@Test func rolloutEpisodeBuildsFiniteWorldModelTrainingTuplesWithoutCrossingEpisodeBoundary() async throws {
    let definition = try makeShortAttitudeScenario(id: "KUY-RL-WM/1", seed: 251)
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: 1)
    let gains = try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2)
    let runner = RolloutRunner(
        schedule: schedule,
        determinism: .tier1Baseline,
        motorNerveRateLimitPerSecond: 100.0,
        motorNerveSmoothingTimeConstant: nil
    )
    let factory = KuyAtt1BaselinePolicyFactory(gains: gains, mode: .teacher)
    let episode = try await runner.runEpisode(definition: definition, policyFactory: factory)

    let tuples = try WorldModelTupleBuilder().makeTuples(from: episode)

    #expect(tuples.count == max(episode.steps.count - 1, 0))
    #expect(tuples.allSatisfy { $0.episodeId == episode.episodeId })
    #expect(tuples.allSatisfy { $0.scenarioId == episode.scenarioId })
    #expect(tuples.allSatisfy { $0.seed == episode.seed })
    #expect(tuples.allSatisfy { $0.reward.isFinite })
    #expect(tuples.allSatisfy { $0.continueValue == 0.0 || $0.continueValue == 1.0 })
    #expect(tuples.last?.continueValue == 0.0)
    #expect(tuples.contains { tuple in
        let prediction = tuple.physicsPrediction.plantState.root.position
        let actual = tuple.actualObservation.plantState.root.position
        return abs(prediction.x - actual.x) > 1e-12
            || abs(prediction.y - actual.y) > 1e-12
            || abs(prediction.z - actual.z) > 1e-12
    })
}

@Test func rolloutRunnerRejectsEpisodesThatExceedConfiguredStepLimit() async throws {
    let definition = try makeShortAttitudeScenario(id: "KUY-RL-LIMIT/1", seed: 301)
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: 1)
    let gains = try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2)
    let runner = RolloutRunner(
        schedule: schedule,
        determinism: .tier1Baseline,
        motorNerveRateLimitPerSecond: 100.0,
        motorNerveSmoothingTimeConstant: nil,
        limits: try RolloutRunner.Limits.validated(maxStepsPerEpisode: 1)
    )
    let factory = KuyAtt1BaselinePolicyFactory(gains: gains, mode: .teacher)

    do {
        _ = try await runner.runEpisode(definition: definition, policyFactory: factory)
        Issue.record("Expected step-limited rollout to fail instead of returning a partial success artifact")
    } catch RolloutRunner.RolloutError.exceededMaxSteps(let scenarioId, let seed, let maxSteps) {
        #expect(scenarioId == definition.config.id.rawValue)
        #expect(seed == definition.config.seed.rawValue)
        #expect(maxSteps == 1)
    } catch {
        Issue.record("Unexpected rollout error: \(error)")
    }
}

@Test func parallelRolloutCancellationDoesNotReturnSilentPartialSuccess() async throws {
    let definitions = try [
        makeShortAttitudeScenario(id: "KUY-RL-CANCEL/1", seed: 401),
        makeShortAttitudeScenario(id: "KUY-RL-CANCEL/2", seed: 402),
    ]
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: 1)
    let gains = try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2)
    let runner = RolloutRunner(
        schedule: schedule,
        determinism: .tier1Baseline,
        motorNerveRateLimitPerSecond: 100.0,
        motorNerveSmoothingTimeConstant: nil
    )
    let collector = try ParallelRolloutCollector(runner: runner, workerCount: 2)
    let factory = KuyAtt1BaselinePolicyFactory(gains: gains, mode: .teacher)
    let task = Task {
        try await collector.collect(definitions: definitions, policyFactory: factory)
    }
    task.cancel()

    var threwCancellation = false
    do {
        _ = try await task.value
        Issue.record("Expected cancelled rollout task to throw")
    } catch RolloutRunner.RolloutError.cancelled {
        threwCancellation = true
    } catch is CancellationError {
        threwCancellation = true
    } catch {
        Issue.record("Unexpected cancellation error: \(error)")
    }
    #expect(threwCancellation)
}

@Test func trainingDatasetMetadataDecodesLegacySchemaAsVersionOne() throws {
    let json = """
    {
      "scenarioId": "legacy",
      "seed": 1,
      "timeStep": 0.001,
      "determinismTier": "tier1",
      "configHash": "abc",
      "channelCount": 6,
      "driveCount": 4,
      "recordCount": 1
    }
    """
    let metadata = try JSONDecoder().decode(TrainingDatasetMetadata.self, from: Data(json.utf8))
    #expect(metadata.schemaVersion == 1)
    #expect(metadata.rewardDescriptor == nil)
}

private actor WorkerConcurrencyProbe {
    private var activeCount = 0
    private var maxActiveCount = 0

    func enter() {
        activeCount += 1
        maxActiveCount = max(maxActiveCount, activeCount)
    }

    func leave() {
        activeCount = max(0, activeCount - 1)
    }

    func maximumActiveCount() -> Int {
        maxActiveCount
    }
}

private struct SlowProbePolicyFactory: ReferenceQuadrotorPolicyFactory {
    let policyID = "slowProbe"
    let probe: WorkerConcurrencyProbe

    func makePolicy(
        definition: ReferenceQuadrotorScenarioDefinition,
        workerIndex: Int
    ) throws -> any ReferenceQuadrotorEnvironmentPolicy {
        SlowProbePolicy(policyID: policyID, probe: probe)
    }
}

private struct SlowProbePolicy: ReferenceQuadrotorEnvironmentPolicy {
    let policyID: String
    let probe: WorkerConcurrencyProbe

    mutating func action(for observation: EnvironmentObservation) async throws -> EnvironmentAction {
        await probe.enter()
        try await Task.sleep(for: .milliseconds(2))
        await probe.leave()
        let drives = try (0..<4).map { index in
            try DriveIntent(index: DriveIndex(UInt32(index)), activation: 0.5)
        }
        return .driveIntents(drives, corrections: [])
    }
}

private func makeShortAttitudeScenario(id: String, seed: UInt64) throws -> ReferenceQuadrotorScenarioDefinition {
    let timeStep = try TimeStep(delta: 0.001)
    let envelope = try SafetyEnvelope(
        omegaSafeMax: 20.0,
        tiltSafeMaxDegrees: 60.0,
        sustainedViolationSeconds: 0.200,
        groundZ: 0.0,
        fallDurationSeconds: 0.5,
        fallVelocityThreshold: 0.05
    )
    let config = try ScenarioConfig(
        id: ScenarioID(id),
        seed: ScenarioSeed(seed),
        duration: 0.02,
        timeStep: timeStep
    )
    return ReferenceQuadrotorScenarioDefinition(
        config: config,
        kind: .hoverStart,
        initialPosition: Axis3(x: 0, y: 0, z: 2.0),
        initialAttitude: EulerAngles.degrees(roll: 5, pitch: 0, yaw: 0),
        initialAngularVelocity: Axis3(x: 0, y: 0, z: 0),
        safetyEnvelope: envelope,
        torqueEvents: [],
        actuatorDegradation: nil,
        gyroDriftScale: 1.0,
        swapEvents: [],
        hfEvents: []
    )
}
