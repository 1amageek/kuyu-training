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

    @Test func defaultConfigUsesBuiltInValidatedValues() {
        let config = CurriculumController.Config.default

        #expect(config.totalLevels == 5)
        #expect(config.scenariosPerLevel == 20)
        #expect(config.advanceThreshold == 0.8)
        #expect(config.maxEpochsPerLevel == 10)
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
        let dir = try makeTemporaryDirectory()
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
        let dir = try makeTemporaryDirectory()
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
        let dir = try makeTemporaryDirectory()
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

    @Test func simulationLogWriterMarksScenarioTerminalBoundary() throws {
        let dir = try makeTemporaryDirectory()
        defer { cleanup(dir) }

        let log = try makeSimulationLog(steps: 3)
        let rewardDescriptor = RewardDescriptor(
            id: "writer-reward",
            version: "1",
            configHash: "writer-reward-hash"
        )
        let taskReference = TrainingTaskReferenceMetadata(
            altitudeHold: TrainingAltitudeHoldReferenceMetadata(
                targetPosition: Axis3(x: 0, y: 0, z: 2),
                tolerance: 0.2,
                referenceVerticalVelocity: 0.5
            )
        )
        let writer = TrainingDatasetWriter()
        _ = try writer.write(
            log: log,
            to: dir,
            rewardDescriptor: rewardDescriptor,
            taskReference: taskReference
        )

        let dataset = try TrainingDataset.load(from: dir)
        #expect(dataset.metadata.done == false)
        #expect(dataset.metadata.truncated == true)
        #expect(dataset.metadata.terminalReason == ScenarioTerminalFacts.completedTerminalReason)
        #expect(dataset.metadata.rewardDescriptor == rewardDescriptor)
        #expect(dataset.metadata.taskReference == taskReference)
        #expect(dataset.records.dropLast().allSatisfy { $0.continueValue == 1.0 })
        #expect(dataset.records.dropLast().allSatisfy { $0.done == false && $0.truncated == false })
        #expect(dataset.records.last?.continueValue == 0.0)
        #expect(dataset.records.last?.done == false)
        #expect(dataset.records.last?.truncated == true)
    }

    @Test func kuyAtt1ExporterUsesEvaluationTerminalFacts() throws {
        let dir = try makeTemporaryDirectory()
        defer { cleanup(dir) }

        let log = try makeSimulationLog(steps: 2)
        let key = ScenarioKey(scenarioId: log.scenarioId, seed: log.seed)
        let evaluation = ScenarioEvaluation(
            scenarioId: log.scenarioId,
            seed: log.seed,
            passed: false,
            maxOmega: 1.0,
            maxTiltDegrees: 10.0,
            sustainedViolationSeconds: 0.2,
            recoveryTimeSeconds: nil,
            overshootDegrees: nil,
            hfStabilityScore: nil,
            failures: [FailureReason.sustainedFall.rawValue],
            failureReason: .sustainedFall,
            failureTime: 0.01
        )
        let output = KuyAtt1RunOutput(
            result: SuiteRunResult(
                evaluations: [evaluation],
                replay: .notPerformed(reason: "Test fixture does not execute replay verification."),
                passed: false
            ),
            summary: ValidationSummary(
                suitePassed: false,
                evaluations: [evaluation],
                replay: .notPerformed(reason: "Test fixture does not execute replay verification."),
                manifest: [],
                aggregate: EvaluationAggregate.from(evaluations: [evaluation])
            ),
            logs: [ScenarioLogEntry(key: key, log: log)]
        )

        let outputs = try TrainingDatasetExporter().write(output: output, to: dir)
        let datasetURL = try #require(outputs[key])
        let dataset = try TrainingDataset.load(from: datasetURL)
        #expect(dataset.metadata.done == true)
        #expect(dataset.metadata.truncated == false)
        #expect(dataset.metadata.terminalReason == FailureReason.sustainedFall.rawValue)
        #expect(dataset.metadata.failureReason == FailureReason.sustainedFall.rawValue)
        #expect(dataset.metadata.failureTime == 0.01)
        #expect(dataset.records.last?.continueValue == 0.0)
        #expect(dataset.records.last?.done == true)
        #expect(dataset.records.last?.truncated == false)
    }

    @Test func trainingScenarioRunOutputExporterUsesEvaluationTerminalFacts() throws {
        let dir = try makeTemporaryDirectory()
        defer { cleanup(dir) }

        let log = try makeSimulationLog(steps: 2)
        let key = ScenarioKey(scenarioId: log.scenarioId, seed: log.seed)
        let evaluation = ScenarioEvaluation(
            scenarioId: log.scenarioId,
            seed: log.seed,
            passed: false,
            maxOmega: 1.0,
            maxTiltDegrees: 10.0,
            sustainedViolationSeconds: 0.2,
            recoveryTimeSeconds: nil,
            overshootDegrees: nil,
            hfStabilityScore: nil,
            failures: [FailureReason.sustainedFall.rawValue],
            failureReason: .sustainedFall,
            failureTime: 0.01
        )
        let kuyAtt1Output = KuyAtt1RunOutput(
            result: SuiteRunResult(
                evaluations: [evaluation],
                replay: .notPerformed(reason: "Test fixture does not execute replay verification."),
                passed: false
            ),
            summary: ValidationSummary(
                suitePassed: false,
                evaluations: [evaluation],
                replay: .notPerformed(reason: "Test fixture does not execute replay verification."),
                manifest: [],
                aggregate: EvaluationAggregate.from(evaluations: [evaluation])
            ),
            logs: [ScenarioLogEntry(key: key, log: log)]
        )

        let output = TrainingScenarioRunOutput(kuyAtt1: kuyAtt1Output)
        let outputs = try TrainingDatasetExporter().write(output: output, to: dir)
        let datasetURL = try #require(outputs[key])
        let dataset = try TrainingDataset.load(from: datasetURL)
        #expect(output.summary.suitePassed == false)
        #expect(output.summary.evaluations.first?.scenarioID == log.scenarioId)
        #expect(dataset.metadata.done == true)
        #expect(dataset.metadata.truncated == false)
        #expect(dataset.metadata.terminalReason == FailureReason.sustainedFall.rawValue)
        #expect(dataset.metadata.failureReason == FailureReason.sustainedFall.rawValue)
        #expect(dataset.metadata.failureTime == 0.01)
    }

    @Test func legacyV3DatasetRemainsLoadableAfterTaskReferenceSchemaUpgrade() throws {
        let dir = try makeTemporaryDirectory()
        defer { cleanup(dir) }

        let metadata = TrainingDatasetMetadata(
            scenarioId: "legacy-v3",
            seed: 3,
            timeStep: 0.005,
            determinismTier: "tier0",
            configHash: "legacy-v3-hash",
            channelCount: 0,
            driveCount: 4,
            recordCount: 1,
            schemaVersion: 3,
            episodeId: "legacy-v3",
            policyId: "manasMojo"
        )
        let record = TrainingDatasetRecord(
            time: 0,
            sensors: [],
            driveIntents: [
                TrainingDriveIntent(driveIndex: 0, value: 0.5),
                TrainingDriveIntent(driveIndex: 1, value: 0),
                TrainingDriveIntent(driveIndex: 2, value: 0),
                TrainingDriveIntent(driveIndex: 3, value: 0),
            ],
            reflexCorrections: [],
            reward: 0,
            done: false,
            truncated: true
        )
        let dataset = TrainingDataset(metadata: metadata, records: [record])

        try TrainingDatasetWriter().write(dataset: dataset, to: dir)

        let loaded = try TrainingDataset.load(from: dir)
        #expect(loaded.metadata.schemaVersion == 3)
        #expect(loaded.metadata.taskReference == nil)
        #expect(loaded.records.count == 1)
    }

    @Test func channelAndDriveCountsReflectMaxIndices() throws {
        let dir = try makeTemporaryDirectory()
        defer { cleanup(dir) }

        let log = try makeSimulationLog(steps: 2, sensorChannels: 4, driveCount: 3)
        let writer = TrainingDatasetWriter()
        _ = try writer.write(log: log, to: dir)

        let metaData = try Data(contentsOf: dir.appendingPathComponent("meta.json"))
        let meta = try JSONDecoder().decode(TrainingDatasetMetadata.self, from: metaData)
        #expect(meta.channelCount == 4)
        #expect(meta.driveCount == 3)
    }

    @Test func writerRejectsInvalidScenarioTerminalFacts() throws {
        let dir = try makeTemporaryDirectory()
        defer { cleanup(dir) }

        let log = try makeSimulationLog(steps: 2)
        let invalidFacts = ScenarioTerminalFacts(
            done: false,
            truncated: true,
            terminalReason: FailureReason.sustainedFall.rawValue,
            failureReason: .sustainedFall,
            failureTime: 0.01
        )

        #expect(throws: ScenarioTerminalFacts.ValidationError.failureRequiresDone(reason: .sustainedFall)) {
            try TrainingDatasetWriter().write(log: log, to: dir, terminalFacts: invalidFacts)
        }
    }

    @Test func actuatorOnlyTeacherActionsBecomeTrainingDriveTargets() throws {
        let dir = try makeTemporaryDirectory()
        defer { cleanup(dir) }

        let log = try makeSimulationLog(steps: 2, driveCount: 0, actuatorCount: 2)
        let writer = TrainingDatasetWriter()
        _ = try writer.write(log: log, to: dir)

        let metaData = try Data(contentsOf: dir.appendingPathComponent("meta.json"))
        let meta = try JSONDecoder().decode(TrainingDatasetMetadata.self, from: metaData)
        #expect(meta.driveCount == 2)

        let records = try String(contentsOf: dir.appendingPathComponent("records.jsonl"), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                try JSONDecoder().decode(TrainingDatasetRecord.self, from: Data(line.utf8))
            }
        #expect(records.allSatisfy { $0.driveIntents.count == 2 })
        #expect(records.first?.driveIntents.map(\.driveIndex) == [0, 1])
    }

    @Test func sparseTeacherActionsAreHeldBetweenCutUpdates() throws {
        let dir = try makeTemporaryDirectory()
        defer { cleanup(dir) }

        let log = try makeSparseDriveSimulationLog()
        let writer = TrainingDatasetWriter()
        _ = try writer.write(log: log, to: dir)

        let records = try String(contentsOf: dir.appendingPathComponent("records.jsonl"), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                try JSONDecoder().decode(TrainingDatasetRecord.self, from: Data(line.utf8))
            }
        #expect(records.map { $0.driveIntents.first?.value } == [nil, 0.8, 0.8, 0.6])
    }

    @Test func emptyLogProducesEmptyRecords() throws {
        let dir = try makeTemporaryDirectory()
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
    driveCount: Int = 1,
    actuatorCount: Int = 0
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
        let actuators = try (0..<actuatorCount).map { actuator in
            try ActuatorValue(
                index: ActuatorIndex(UInt32(actuator)),
                value: 0.25 + Double(actuator) * 0.1
            )
        }
        return try WorldStepLog(
            time: WorldTime(stepIndex: UInt64(index), time: Double(index) * 0.01),
            events: [.timeAdvance, .logging],
            sensorSamples: sensors,
            driveIntents: drives,
            reflexCorrections: [],
            actuatorValues: actuators,
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

private func makeSparseDriveSimulationLog() throws -> SimulationLog {
    let drivesByStep: [[DriveIntent]] = [
        [],
        [try DriveIntent(index: DriveIndex(0), activation: 0.8, parameters: [])],
        [],
        [try DriveIntent(index: DriveIndex(0), activation: 0.6, parameters: [])]
    ]
    let stepLogs = try drivesByStep.enumerated().map { index, drives in
        try WorldStepLog(
            time: WorldTime(stepIndex: UInt64(index), time: Double(index) * 0.01),
            events: [.timeAdvance, .logging],
            sensorSamples: [
                ChannelSample(channelIndex: 0, value: 0.0, timestamp: Double(index) * 0.01),
            ],
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
        scenarioId: ScenarioID("sparse-writer-test"),
        seed: ScenarioSeed(42),
        timeStep: TimeStep(delta: 0.01),
        determinism: DeterminismConfig(tier: .tier0, tier1Tolerance: nil),
        configHash: "sparse-test-hash",
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

private func makeTemporaryDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-training-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func cleanup(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove temporary directory \(url.path): \(error)")
    }
}
