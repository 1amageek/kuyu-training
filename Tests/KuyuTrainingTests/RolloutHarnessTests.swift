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
        policyId: "manasMojo",
        snapshotId: "snapshot-a",
        robotManifestId: "robot-a",
        modelPath: "/tmp/model",
        configHash: "hash-a"
    )

    #expect(snapshot.policyId == "manasMojo")
    #expect(snapshot.snapshotId == "snapshot-a")
    #expect(snapshot.robotManifestId == "robot-a")
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

@Test func rolloutRunnerUsesWorkerScopedPolicyFactoryForEachWorker() async throws {
    let definitions = try (0..<4).map { index in
        try makeShortAttitudeScenario(id: "KUY-RL-WORKER-SCOPE/\(index)", seed: UInt64(700 + index))
    }
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: 1)
    let runner = RolloutRunner(
        schedule: schedule,
        determinism: .tier1Baseline,
        motorNerveRateLimitPerSecond: 100.0,
        motorNerveSmoothingTimeConstant: nil
    )
    let factory = ScopedProbePolicyFactory()

    let serial = try await runner.run(definitions: [definitions[0]], policyFactory: factory, workerIndex: 7)
    #expect(serial.map(\.policyId) == ["scoped-worker-7"])

    let parallel = try await ParallelRolloutCollector(runner: runner, workerCount: 2)
        .collect(definitions: definitions, policyFactory: factory)
    #expect(Set(parallel.map(\.policyId)) == Set(["scoped-worker-0", "scoped-worker-1"]))
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
    #expect(meta.purpose == .reinforcementRollout)
    #expect(meta.physicsTimeStep == definition.config.timeStep.delta)
    #expect(meta.controlPeriodSteps == 1)
    #expect(meta.policyId == "teacherActiveAltitudeHold")
    #expect(meta.rewardSum == episode.rewardSum)
    #expect(meta.rewardDescriptor == episode.rewardDescriptor)
    #expect(meta.taskReference == episode.taskReference)
    #expect(meta.done == episode.done)
    #expect(meta.truncated == episode.truncated)
    #expect(meta.terminalReason == episode.terminalReason)
    #expect(record.reward != nil)
    #expect(record.episodeId == episode.episodeId)
    #expect(record.policyDecisionID == episode.transitions?.first?.decisionID)
    #expect(record.actionObservationTime == episode.transitions?.first?.actionObservation.time.time)
    #expect(record.actionObservationState?.count == 13)
    #expect(record.physicsState?.count == 13)
    #expect(record.actualState?.count == 13)
    #expect(record.actionValues?.isEmpty == false)
    #expect(record.actuatorCommandValues?.isEmpty == false)
    #expect(record.continueValue == 0.0 || record.continueValue == 1.0)
    #expect(records.last?.done == episode.done)
    #expect(records.last?.truncated == episode.truncated)
    #expect(records.last?.continueValue == 0.0)
    #expect(records.dropFirst().contains { record in
        guard let physics = record.physicsState, let actual = record.actualState else { return false }
        return zip(physics, actual).contains { abs($0 - $1) > 1e-12 }
    })
}

@Test func rolloutRunnerPreservesCausalTransitionsAcrossControlPeriods() async throws {
    for (controlPeriodSteps, duration) in [(UInt64(2), 0.018), (UInt64(3), 0.020)] {
        let definition = try makeShortAttitudeScenario(
            id: "KUY-RL-CAUSAL/\(controlPeriodSteps)",
            seed: 230 + controlPeriodSteps,
            duration: duration
        )
        let runner = RolloutRunner(
            schedule: try SimulationSchedule.baseline(cutPeriodSteps: controlPeriodSteps),
            determinism: .tier1Baseline,
            motorNerveRateLimitPerSecond: 100.0,
            motorNerveSmoothingTimeConstant: nil
        )
        let gains = try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2)
        let episode = try await runner.runEpisode(
            definition: definition,
            policyFactory: KuyAtt1BaselinePolicyFactory(gains: gains, mode: .teacher)
        )
        let transitions = try #require(episode.transitions)
        let physicsStepCount = Int((duration / definition.config.timeStep.delta).rounded(.down))
        let expectedCount = (physicsStepCount + Int(controlPeriodSteps) - 1) / Int(controlPeriodSteps)
        let expectedDuration = definition.config.timeStep.delta * Double(controlPeriodSteps)

        #expect(episode.steps.count == expectedCount)
        #expect(transitions.count == expectedCount)
        #expect(Set(transitions.map(\.decisionID)).count == expectedCount)
        #expect(transitions.dropLast().allSatisfy { abs($0.duration - expectedDuration) <= 1.0e-12 })
        let expectedFinalDuration = definition.config.timeStep.delta
            * Double(physicsStepCount - (expectedCount - 1) * Int(controlPeriodSteps))
        #expect(abs((transitions.last?.duration ?? 0) - expectedFinalDuration) <= 1.0e-12)
        for index in transitions.indices.dropFirst() {
            #expect(transitions[index].actionObservation == transitions[index - 1].outcome.observation)
        }

        let dataset = TrainingDatasetWriter().makeDataset(
            episode: episode,
            timeStep: definition.config.timeStep.delta,
            determinismTier: "tier1"
        )
        try TrainingDatasetContractValidator().validate(
            dataset,
            against: TrainingDatasetContract(
                requiresTerminalFacts: true,
                requiresCausalTransitions: true
            )
        )
        #expect(dataset.metadata.timeStep == expectedDuration)
        #expect(dataset.metadata.physicsTimeStep == definition.config.timeStep.delta)
        #expect(dataset.metadata.controlPeriodSteps == controlPeriodSteps)
        #expect(dataset.records.map(\.policyDecisionID) == transitions.map { Optional($0.decisionID) })
        #expect(dataset.records.map(\.actionObservationTime) == transitions.map { Optional($0.actionObservation.time.time) })
        for (record, transition) in zip(dataset.records, transitions) {
            #expect(record.actionValues == transition.action.driveIntents.map(\.activation))
            #expect(record.driveIntents.map(\.value) == transition.action.driveIntents.map(\.activation))
            #expect(record.actuatorCommandValues == transition.outcome.log.actuatorValues.map(\.value))
        }
    }
}

@Test func rolloutRunnerPersistsShortTerminalFailureTransition() async throws {
    let definition = try makeShortAttitudeScenario(
        id: "KUY-RL-CAUSAL/SHORT-TERMINAL",
        seed: 241,
        duration: 0.018,
        groundZ: 3.0
    )
    let runner = RolloutRunner(
        schedule: try SimulationSchedule.baseline(cutPeriodSteps: 3),
        determinism: .tier1Baseline,
        motorNerveRateLimitPerSecond: 100.0,
        motorNerveSmoothingTimeConstant: nil
    )
    let gains = try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2)

    let episode = try await runner.runEpisode(
        definition: definition,
        policyFactory: KuyAtt1BaselinePolicyFactory(gains: gains, mode: .teacher)
    )
    let transitions = try #require(episode.transitions)
    let transition = try #require(transitions.first)
    let dataset = TrainingDatasetWriter().makeDataset(
        episode: episode,
        timeStep: definition.config.timeStep.delta,
        determinismTier: "tier1"
    )

    #expect(episode.done)
    #expect(!episode.truncated)
    #expect(transitions.count == 1)
    #expect(transition.outcome.info.failureReason == .groundViolation)
    #expect(abs(transition.duration - definition.config.timeStep.delta) <= 1.0e-12)
    #expect(dataset.metadata.timeStep == definition.config.timeStep.delta * 3.0)
    #expect(dataset.records.count == 1)
    #expect(dataset.records.first?.time == definition.config.timeStep.delta)
    try TrainingDatasetContractValidator().validate(
        dataset,
        against: TrainingDatasetContract(
            requiresTerminalFacts: true,
            requiresCausalTransitions: true
        )
    )
}

@Test func rolloutDatasetRejectsDirectActuatorActionInsteadOfRelabelingItAsDriveIntent() async throws {
    let definition = try makeShortAttitudeScenario(id: "KUY-RL-CAUSAL/DIRECT", seed: 242)
    let runner = RolloutRunner(
        schedule: try SimulationSchedule.baseline(cutPeriodSteps: 1),
        determinism: .tier1Baseline,
        motorNerveRateLimitPerSecond: 100.0,
        motorNerveSmoothingTimeConstant: nil
    )
    let episode = try await runner.runEpisode(
        definition: definition,
        policyFactory: DirectActuatorPolicyFactory()
    )
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-direct-action-\(UUID().uuidString)", isDirectory: true)

    #expect(
        throws: TrainingDatasetContractValidator.ValidationError.missingPolicyAction(recordIndex: 0)
    ) {
        _ = try TrainingDatasetWriter().write(
            episode: episode,
            timeStep: definition.config.timeStep.delta,
            determinismTier: "tier1",
            to: root
        )
    }
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

    let transitions = try #require(episode.transitions)
    #expect(tuples.count == transitions.count)
    #expect(tuples.allSatisfy { $0.episodeId == episode.episodeId })
    #expect(tuples.allSatisfy { $0.scenarioId == episode.scenarioId })
    #expect(tuples.allSatisfy { $0.seed == episode.seed })
    #expect(tuples.allSatisfy { $0.reward.isFinite })
    #expect(tuples.allSatisfy { $0.continueValue == 0.0 || $0.continueValue == 1.0 })
    #expect(tuples.last?.continueValue == 0.0)
    for (tuple, transition) in zip(tuples, transitions) {
        #expect(tuple.observation == transition.actionObservation)
        #expect(tuple.action == transition.action)
        #expect(tuple.actualObservation == transition.outcome.observation)
        #expect(tuple.reward == transition.outcome.reward)
    }
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

private struct ScopedProbePolicyFactory: ReferenceQuadrotorWorkerScopedPolicyFactory {
    let policyID = "scoped-root"

    func makeWorkerPolicyFactory(workerIndex: Int) throws -> any ReferenceQuadrotorPolicyFactory {
        ScopedProbeWorkerPolicyFactory(workerIndex: workerIndex)
    }

    func makePolicy(
        definition: ReferenceQuadrotorScenarioDefinition,
        workerIndex: Int
    ) throws -> any ReferenceQuadrotorEnvironmentPolicy {
        _ = definition
        return ScopedProbePolicy(policyID: "unscoped-worker-\(workerIndex)")
    }
}

private struct ScopedProbeWorkerPolicyFactory: ReferenceQuadrotorPolicyFactory {
    let workerIndex: Int
    var policyID: String { "scoped-worker-\(workerIndex)" }

    func makePolicy(
        definition: ReferenceQuadrotorScenarioDefinition,
        workerIndex: Int
    ) throws -> any ReferenceQuadrotorEnvironmentPolicy {
        _ = definition
        _ = workerIndex
        return ScopedProbePolicy(policyID: policyID)
    }
}

private struct ScopedProbePolicy: ReferenceQuadrotorEnvironmentPolicy {
    let policyID: String

    mutating func action(for observation: EnvironmentObservation) async throws -> EnvironmentAction {
        _ = observation
        let drives = try (0..<4).map { index in
            try DriveIntent(index: DriveIndex(UInt32(index)), activation: 0.5)
        }
        return .driveIntents(drives, corrections: [])
    }
}

private struct DirectActuatorPolicyFactory: ReferenceQuadrotorPolicyFactory {
    let policyID = "direct-actuator-test"

    func makePolicy(
        definition: ReferenceQuadrotorScenarioDefinition,
        workerIndex: Int
    ) throws -> any ReferenceQuadrotorEnvironmentPolicy {
        _ = definition
        _ = workerIndex
        return DirectActuatorPolicy(policyID: policyID)
    }
}

private struct DirectActuatorPolicy: ReferenceQuadrotorEnvironmentPolicy {
    let policyID: String

    mutating func action(for observation: EnvironmentObservation) async throws -> EnvironmentAction {
        _ = observation
        return .actuatorValues(
            try (0..<4).map { index in
                try ActuatorValue(index: ActuatorIndex(UInt32(index)), value: 0.5)
            }
        )
    }
}

private func makeShortAttitudeScenario(
    id: String,
    seed: UInt64,
    duration: Double = 0.02,
    groundZ: Double = 0.0
) throws -> ReferenceQuadrotorScenarioDefinition {
    let timeStep = try TimeStep(delta: 0.001)
    let envelope = try SafetyEnvelope(
        omegaSafeMax: 20.0,
        tiltSafeMaxDegrees: 60.0,
        sustainedViolationSeconds: 0.200,
        groundZ: groundZ,
        fallDurationSeconds: 0.5,
        fallVelocityThreshold: 0.05
    )
    let config = try ScenarioConfig(
        id: ScenarioID(id),
        seed: ScenarioSeed(seed),
        duration: duration,
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
