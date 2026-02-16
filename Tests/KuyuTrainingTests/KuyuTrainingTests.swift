import Foundation
import Testing
import KuyuCore
import KuyuPhysics
import KuyuScenarios
@testable import KuyuTraining

// MARK: - OnlineDataBuffer

@Suite("OnlineDataBuffer")
struct OnlineDataBufferTests {

    @Test func rejectsZeroCapacity() {
        #expect(throws: OnlineDataBuffer.ValidationError.nonPositiveMaxRecords) {
            try OnlineDataBuffer(maxRecords: 0)
        }
    }

    @Test func rejectsNegativeCapacity() {
        #expect(throws: OnlineDataBuffer.ValidationError.nonPositiveMaxRecords) {
            try OnlineDataBuffer(maxRecords: -1)
        }
    }

    @Test func appendFillsUpToCapacity() throws {
        let buffer = try OnlineDataBuffer(maxRecords: 3)
        for i in 0..<3 {
            buffer.append(makeRecord(time: Double(i)))
        }
        #expect(buffer.count == 3)
        #expect(buffer.totalWritten == 3)
    }

    @Test func ringBufferOverwritesOldest() throws {
        let buffer = try OnlineDataBuffer(maxRecords: 3)
        for i in 0..<5 {
            buffer.append(makeRecord(time: Double(i)))
        }
        #expect(buffer.count == 3)
        #expect(buffer.totalWritten == 5)

        let records = buffer.allRecords()
        // 0,1 were overwritten by 3,4 → remaining: [2, 3, 4]
        #expect(records.map(\.time) == [2.0, 3.0, 4.0])
    }

    @Test func allRecordsPreservesInsertionOrderBeforeWrap() throws {
        let buffer = try OnlineDataBuffer(maxRecords: 5)
        for i in 0..<3 {
            buffer.append(makeRecord(time: Double(i)))
        }
        let records = buffer.allRecords()
        #expect(records.map(\.time) == [0.0, 1.0, 2.0])
    }

    @Test func sampleReturnsRequestedCount() throws {
        let buffer = try OnlineDataBuffer(maxRecords: 10)
        for i in 0..<5 {
            buffer.append(makeRecord(time: Double(i)))
        }
        var rng = SplitMix64(seed: 42)
        let sampled = buffer.sample(count: 3, rng: &rng)
        #expect(sampled.count == 3)
    }

    @Test func sampleFromEmptyReturnsEmpty() throws {
        let buffer = try OnlineDataBuffer(maxRecords: 10)
        var rng = SplitMix64(seed: 42)
        let sampled = buffer.sample(count: 5, rng: &rng)
        #expect(sampled.isEmpty)
    }

    @Test func clearResetsCountButPreservesTotalWritten() throws {
        let buffer = try OnlineDataBuffer(maxRecords: 10)
        for i in 0..<4 {
            buffer.append(makeRecord(time: Double(i)))
        }
        let totalBefore = buffer.totalWritten
        buffer.clear()
        #expect(buffer.count == 0)
        #expect(buffer.allRecords().isEmpty)
        #expect(buffer.totalWritten == totalBefore)
    }
}

// MARK: - CurriculumController

@Suite("CurriculumController")
struct CurriculumControllerTests {

    @Test func configRejectsInvalidValues() {
        #expect(throws: CurriculumController.Config.ValidationError.nonPositive("totalLevels")) {
            try CurriculumController.Config(totalLevels: 0)
        }
        #expect(throws: CurriculumController.Config.ValidationError.nonPositive("scenariosPerLevel")) {
            try CurriculumController.Config(scenariosPerLevel: 0)
        }
        #expect(throws: CurriculumController.Config.ValidationError.nonPositive("maxEpochsPerLevel")) {
            try CurriculumController.Config(maxEpochsPerLevel: 0)
        }
        #expect(throws: CurriculumController.Config.ValidationError.outOfRange("advanceThreshold")) {
            try CurriculumController.Config(advanceThreshold: 0.0)
        }
        #expect(throws: CurriculumController.Config.ValidationError.outOfRange("advanceThreshold")) {
            try CurriculumController.Config(advanceThreshold: 1.1)
        }
    }

    @Test func configAcceptsBoundaryValues() throws {
        let config = try CurriculumController.Config(
            totalLevels: 1, scenariosPerLevel: 1,
            advanceThreshold: 1.0, maxEpochsPerLevel: 1
        )
        #expect(config.advanceThreshold == 1.0)
    }

    @Test func advancesWhenPassRateMeetsThreshold() throws {
        let config = try CurriculumController.Config(
            totalLevels: 3, scenariosPerLevel: 2,
            advanceThreshold: 0.5, maxEpochsPerLevel: 10
        )
        var controller = CurriculumController(config: config)
        #expect(controller.currentLevel == 0)

        // 1/2 pass → 50% == threshold → advance
        let evals = [
            try makeEvaluation(passed: true),
            try makeEvaluation(passed: false),
        ]
        let result = controller.report(evaluations: evals)
        #expect(result == .advanced(newLevel: 1))
        #expect(controller.currentLevel == 1)
        #expect(controller.epochsAtCurrentLevel == 0)
    }

    @Test func staysWhenPassRateBelowThreshold() throws {
        let config = try CurriculumController.Config(
            totalLevels: 3, scenariosPerLevel: 2,
            advanceThreshold: 0.8, maxEpochsPerLevel: 10
        )
        var controller = CurriculumController(config: config)

        let evals = [
            try makeEvaluation(passed: true),
            try makeEvaluation(passed: false),
        ]
        let result = controller.report(evaluations: evals)
        #expect(result == .stayAtLevel(currentLevel: 0, passRate: 0.5))
        #expect(controller.currentLevel == 0)
        #expect(controller.epochsAtCurrentLevel == 1)
    }

    @Test func maxEpochsReachedForcesAdvance() throws {
        let config = try CurriculumController.Config(
            totalLevels: 3, scenariosPerLevel: 2,
            advanceThreshold: 1.0, maxEpochsPerLevel: 2
        )
        var controller = CurriculumController(config: config)

        let failEvals = [try makeEvaluation(passed: false)]

        // epoch 1: stay
        let r1 = controller.report(evaluations: failEvals)
        #expect(r1 == .stayAtLevel(currentLevel: 0, passRate: 0.0))

        // epoch 2: maxEpochs → forced advance
        let r2 = controller.report(evaluations: failEvals)
        #expect(r2 == .maxEpochsReached(level: 0))
        #expect(controller.currentLevel == 1)
    }

    @Test func completedWhenAllLevelsFinished() throws {
        let config = try CurriculumController.Config(
            totalLevels: 2, scenariosPerLevel: 1,
            advanceThreshold: 0.5, maxEpochsPerLevel: 10
        )
        var controller = CurriculumController(config: config)
        let passEvals = [try makeEvaluation(passed: true)]

        let r1 = controller.report(evaluations: passEvals)
        #expect(r1 == .advanced(newLevel: 1))

        let r2 = controller.report(evaluations: passEvals)
        #expect(r2 == .completed)
        #expect(controller.isComplete)
    }

    @Test func reportAfterCompletionAlwaysReturnsCompleted() throws {
        let config = try CurriculumController.Config(
            totalLevels: 1, scenariosPerLevel: 1,
            advanceThreshold: 0.5, maxEpochsPerLevel: 10
        )
        var controller = CurriculumController(config: config)
        let passEvals = [try makeEvaluation(passed: true)]

        let r1 = controller.report(evaluations: passEvals)
        #expect(r1 == .completed)

        // 完了後の追加 report は常に .completed
        let r2 = controller.report(evaluations: passEvals)
        #expect(r2 == .completed)
    }

    @Test func levelHistoryAccumulatesAcrossLevels() throws {
        let config = try CurriculumController.Config(
            totalLevels: 3, scenariosPerLevel: 1,
            advanceThreshold: 0.5, maxEpochsPerLevel: 10
        )
        var controller = CurriculumController(config: config)
        let passEvals = [try makeEvaluation(passed: true)]

        _ = controller.report(evaluations: passEvals) // level 0 → 1
        _ = controller.report(evaluations: passEvals) // level 1 → 2
        _ = controller.report(evaluations: passEvals) // level 2 → completed

        #expect(controller.levelHistory.count == 3)
        #expect(controller.levelHistory.map(\.level) == [0, 1, 2])
    }

    @Test func progressReflectsCurrentLevel() throws {
        let config = try CurriculumController.Config(
            totalLevels: 4, scenariosPerLevel: 1,
            advanceThreshold: 0.5, maxEpochsPerLevel: 10
        )
        var controller = CurriculumController(config: config)
        #expect(controller.progress == 0.0)

        let passEvals = [try makeEvaluation(passed: true)]
        _ = controller.report(evaluations: passEvals)
        #expect(controller.progress == 0.25)
    }

    @Test func emptyEvaluationsNeverAdvance() throws {
        let config = try CurriculumController.Config(
            totalLevels: 3, scenariosPerLevel: 1,
            advanceThreshold: 0.5, maxEpochsPerLevel: 10
        )
        var controller = CurriculumController(config: config)
        let result = controller.report(evaluations: [])
        #expect(result == .stayAtLevel(currentLevel: 0, passRate: 0.0))
    }
}

// MARK: - ParallelDataCollector

@Suite("ParallelDataCollector")
struct ParallelDataCollectorTests {

    @Test func collectAddsRecordsToBufferAndReturnsCount() throws {
        let buffer = try OnlineDataBuffer(maxRecords: 100)
        let collector = ParallelDataCollector(buffer: buffer)

        let (logs, definitions) = try makeLogAndDefinitionPair(stepCounts: [3, 2])
        let result = try collector.collect(logs: logs, definitions: definitions)

        #expect(result.recordsCollected == 5)
        #expect(buffer.count == 5)
        #expect(result.evaluations.count == 2)
    }

    @Test func collectRejectsCountMismatch() throws {
        let buffer = try OnlineDataBuffer(maxRecords: 100)
        let collector = ParallelDataCollector(buffer: buffer)

        let (logs, _) = try makeLogAndDefinitionPair(stepCounts: [2, 3])
        let (_, defs) = try makeLogAndDefinitionPair(stepCounts: [1])

        #expect(throws: ParallelDataCollector.CollectionError.countMismatch(logsCount: 2, definitionsCount: 1)) {
            try collector.collect(logs: logs, definitions: defs)
        }
    }

    @Test func collectWithEmptyInputsSucceeds() throws {
        let buffer = try OnlineDataBuffer(maxRecords: 100)
        let collector = ParallelDataCollector(buffer: buffer)

        let result = try collector.collect(logs: [], definitions: [])
        #expect(result.recordsCollected == 0)
        #expect(result.evaluations.isEmpty)
        #expect(buffer.count == 0)
    }
}

// MARK: - AutoLabeler

@Suite("AutoLabeler")
struct AutoLabelerTests {

    @Test func failedEvaluationProducesFailedLabel() throws {
        let labeler = AutoLabeler()
        let eval = try makeEvaluation(passed: false, maxTiltDegrees: 50, maxOmega: 20)
        let label = labeler.label(evaluation: eval)
        #expect(label.quality == .failed)
        #expect(label.score == 0)
        #expect(!label.passed)
    }

    @Test func excellentForLowTiltAndOmega() throws {
        let labeler = AutoLabeler()
        let eval = try makeEvaluation(passed: true, maxTiltDegrees: 2, maxOmega: 1)
        let label = labeler.label(evaluation: eval)
        #expect(label.quality == .excellent)
        #expect(label.passed)
        #expect(label.score > 0.8)
    }

    @Test func goodForModerateTiltAndOmega() throws {
        let labeler = AutoLabeler()
        let eval = try makeEvaluation(passed: true, maxTiltDegrees: 10, maxOmega: 5)
        let label = labeler.label(evaluation: eval)
        #expect(label.quality == .good)
        #expect(label.score > 0.5)
    }

    @Test func marginalForHighTilt() throws {
        let labeler = AutoLabeler()
        let eval = try makeEvaluation(passed: true, maxTiltDegrees: 25, maxOmega: 1)
        let label = labeler.label(evaluation: eval)
        #expect(label.quality == .marginal)
    }

    @Test func scoreIsAlwaysBoundedZeroToOne() throws {
        let labeler = AutoLabeler()
        // Extreme values that could push score formula negative
        let eval = try makeEvaluation(passed: true, maxTiltDegrees: 60, maxOmega: 30)
        let label = labeler.label(evaluation: eval)
        #expect(label.score >= 0)
        #expect(label.score <= 1)
    }

    @Test func customThresholdsAffectClassification() throws {
        let strict = AutoLabeler(thresholds: AutoLabeler.Thresholds(
            excellentMaxTilt: 1.0, goodMaxTilt: 3.0, marginalMaxTilt: 5.0,
            excellentMaxOmega: 0.5, goodMaxOmega: 2.0
        ))
        // Under default thresholds this is excellent, under strict it's good
        let eval = try makeEvaluation(passed: true, maxTiltDegrees: 2, maxOmega: 1)
        let label = strict.label(evaluation: eval)
        #expect(label.quality == .good)
    }
}

// MARK: - TrainingDatasetWriter

@Suite("TrainingDatasetWriter")
struct TrainingDatasetWriterTests {

    @Test func writesMetaAndRecordsFiles() throws {
        let dir = makeTemporaryDirectory()
        defer { cleanup(dir) }

        let log = try makeSimulationLog(steps: 3)
        let writer = TrainingDatasetWriter()
        let result = try writer.write(log: log, to: dir)
        #expect(result == dir)

        let metaURL = dir.appendingPathComponent("meta.json")
        let recordsURL = dir.appendingPathComponent("records.jsonl")
        #expect(FileManager.default.fileExists(atPath: metaURL.path))
        #expect(FileManager.default.fileExists(atPath: recordsURL.path))
    }

    @Test func metadataMatchesInput() throws {
        let dir = makeTemporaryDirectory()
        defer { cleanup(dir) }

        let log = try makeSimulationLog(steps: 4)
        let writer = TrainingDatasetWriter()
        _ = try writer.write(log: log, to: dir)

        let metaData = try Data(contentsOf: dir.appendingPathComponent("meta.json"))
        let meta = try JSONDecoder().decode(TrainingDatasetMetadata.self, from: metaData)
        #expect(meta.scenarioId == log.scenarioId.rawValue)
        #expect(meta.seed == log.seed.rawValue)
        #expect(meta.recordCount == 4)
        #expect(meta.timeStep == log.timeStep.delta)
    }

    @Test func recordsJsonlHasOneLinePerEvent() throws {
        let dir = makeTemporaryDirectory()
        defer { cleanup(dir) }

        let log = try makeSimulationLog(steps: 5)
        let writer = TrainingDatasetWriter()
        _ = try writer.write(log: log, to: dir)

        let content = try String(contentsOf: dir.appendingPathComponent("records.jsonl"), encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 5)

        // Each line is valid JSON
        for line in lines {
            let data = Data(line.utf8)
            let record = try JSONDecoder().decode(TrainingDatasetRecord.self, from: data)
            #expect(record.time >= 0)
        }
    }

    @Test func channelAndDriveCountsReflectMaxIndices() throws {
        let dir = makeTemporaryDirectory()
        defer { cleanup(dir) }

        let log = try makeSimulationLog(steps: 2, sensorChannels: 4, driveCount: 3)
        let writer = TrainingDatasetWriter()
        _ = try writer.write(log: log, to: dir)

        let metaData = try Data(contentsOf: dir.appendingPathComponent("meta.json"))
        let meta = try JSONDecoder().decode(TrainingDatasetMetadata.self, from: metaData)
        #expect(meta.channelCount == 4)
        #expect(meta.driveCount == 3)
    }

    @Test func emptyLogProducesEmptyRecords() throws {
        let dir = makeTemporaryDirectory()
        defer { cleanup(dir) }

        let log = try makeSimulationLog(steps: 0)
        let writer = TrainingDatasetWriter()
        _ = try writer.write(log: log, to: dir)

        let metaData = try Data(contentsOf: dir.appendingPathComponent("meta.json"))
        let meta = try JSONDecoder().decode(TrainingDatasetMetadata.self, from: metaData)
        #expect(meta.recordCount == 0)
        #expect(meta.channelCount == 0)
        #expect(meta.driveCount == 0)
    }
}

// MARK: - Test Helpers

private func makeRecord(time: Double) -> TrainingDatasetRecord {
    TrainingDatasetRecord(
        time: time,
        sensors: [],
        driveIntents: [],
        reflexCorrections: []
    )
}

private func makeEvaluation(
    passed: Bool,
    maxTiltDegrees: Double = 5.0,
    maxOmega: Double = 1.0
) throws -> ExtendedScenarioEvaluation {
    let base = ScenarioEvaluation(
        scenarioId: try ScenarioID("test"),
        seed: ScenarioSeed(1),
        passed: passed,
        maxOmega: maxOmega,
        maxTiltDegrees: maxTiltDegrees,
        sustainedViolationSeconds: 0,
        recoveryTimeSeconds: nil,
        overshootDegrees: nil,
        hfStabilityScore: nil,
        failures: passed ? [] : ["safety-violation"]
    )
    return ExtendedScenarioEvaluation(base: base, controlQuality: nil, inverseDynamics: nil)
}

private func makeDefinition(id: String, seed: UInt64) throws -> ReferenceQuadrotorScenarioDefinition {
    let config = try ScenarioConfig(
        id: ScenarioID(id),
        seed: ScenarioSeed(seed),
        duration: 0.05,
        timeStep: TimeStep(delta: 0.01)
    )
    let envelope = try SafetyEnvelope(
        omegaSafeMax: 20,
        tiltSafeMaxDegrees: 60,
        sustainedViolationSeconds: 0.2,
        groundZ: 0.0,
        fallDurationSeconds: 0.5,
        fallVelocityThreshold: 0.0
    )
    return ReferenceQuadrotorScenarioDefinition(
        config: config,
        kind: .hoverStart,
        initialPosition: Axis3(x: 0, y: 0, z: 2),
        initialAttitude: EulerAngles(roll: 0, pitch: 0, yaw: 0),
        initialAngularVelocity: Axis3(x: 0, y: 0, z: 0),
        safetyEnvelope: envelope,
        torqueEvents: [],
        actuatorDegradation: nil,
        gyroDriftScale: 1.0,
        swapEvents: [],
        hfEvents: []
    )
}

private func makeSimulationLog(
    steps: Int,
    sensorChannels: Int = 1,
    driveCount: Int = 1
) throws -> SimulationLog {
    let stepLogs = try (0..<steps).map { index in
        let sensors = try (0..<sensorChannels).map { ch in
            try ChannelSample(
                channelIndex: UInt32(ch),
                value: Double(ch) * 0.1,
                timestamp: Double(index) * 0.01
            )
        }
        let drives = try (0..<driveCount).map { d in
            try DriveIntent(
                index: DriveIndex(UInt32(d)),
                activation: 0.5,
                parameters: []
            )
        }
        return try WorldStepLog(
            time: WorldTime(stepIndex: UInt64(index), time: Double(index) * 0.01),
            events: [.timeAdvance, .logging],
            sensorSamples: sensors,
            driveIntents: drives,
            reflexCorrections: [],
            actuatorValues: [],
            actuatorTelemetry: ActuatorTelemetrySnapshot(channels: []),
            safetyTrace: SafetyTrace(omegaMagnitude: 0.0, tiltRadians: 0.0),
            plantState: PlantStateSnapshot(
                root: RigidBodySnapshot(
                    id: "root",
                    position: Axis3(x: 0, y: 0, z: 2),
                    velocity: Axis3(x: 0, y: 0, z: 0),
                    orientation: QuaternionSnapshot(w: 1, x: 0, y: 0, z: 0),
                    angularVelocity: Axis3(x: 0, y: 0, z: 0)
                )
            ),
            disturbances: DisturbanceSnapshot(
                forceWorld: Axis3(x: 0, y: 0, z: 0),
                torqueBody: Axis3(x: 0, y: 0, z: 0)
            )
        )
    }
    return try SimulationLog(
        scenarioId: ScenarioID("writer-test"),
        seed: ScenarioSeed(42),
        timeStep: TimeStep(delta: 0.01),
        determinism: DeterminismConfig(tier: .tier0, tier1Tolerance: nil),
        configHash: "test-hash",
        events: stepLogs
    )
}

private func makeLogAndDefinitionPair(
    stepCounts: [Int]
) throws -> ([SimulationLog], [ReferenceQuadrotorScenarioDefinition]) {
    var logs: [SimulationLog] = []
    var defs: [ReferenceQuadrotorScenarioDefinition] = []
    for (i, count) in stepCounts.enumerated() {
        let id = "scenario-\(i)"
        let seed = UInt64(i + 1)
        let stepLogs = try (0..<count).map { index in
            try WorldStepLog(
                time: WorldTime(stepIndex: UInt64(index), time: Double(index) * 0.01),
                events: [.timeAdvance],
                sensorSamples: [],
                driveIntents: [],
                reflexCorrections: [],
                actuatorValues: [],
                actuatorTelemetry: ActuatorTelemetrySnapshot(channels: []),
                safetyTrace: SafetyTrace(omegaMagnitude: 0.0, tiltRadians: 0.0),
                plantState: PlantStateSnapshot(
                    root: RigidBodySnapshot(
                        id: "root",
                        position: Axis3(x: 0, y: 0, z: 2),
                        velocity: Axis3(x: 0, y: 0, z: 0),
                        orientation: QuaternionSnapshot(w: 1, x: 0, y: 0, z: 0),
                        angularVelocity: Axis3(x: 0, y: 0, z: 0)
                    )
                ),
                disturbances: DisturbanceSnapshot(
                    forceWorld: Axis3(x: 0, y: 0, z: 0),
                    torqueBody: Axis3(x: 0, y: 0, z: 0)
                )
            )
        }
        let log = try SimulationLog(
            scenarioId: ScenarioID(id),
            seed: ScenarioSeed(seed),
            timeStep: TimeStep(delta: 0.01),
            determinism: DeterminismConfig(tier: .tier0, tier1Tolerance: nil),
            configHash: "cfg-\(id)",
            events: stepLogs
        )
        logs.append(log)
        defs.append(try makeDefinition(id: id, seed: seed))
    }
    return (logs, defs)
}

private func makeTemporaryDirectory() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-training-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}
