import Foundation
import Testing
@testable import KuyuTraining

@Suite("TrainingRunContract")
struct TrainingRunContractTests {
    // MARK: - Fixtures

    private func makeTemporaryRunRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuyu-run-contract-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeManifest(
        runID: String,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        tier: Int = 0,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) -> TrainingRunManifest {
        TrainingRunManifest(
            runID: TrainingRunID(runID),
            createdAt: createdAt,
            task: "attitude-rr-ppo",
            profile: "P1",
            semanticVersion: "ppo-run-v42",
            cacheKey: "cache-abc",
            code: TrainingRunManifest.CodeIdentity(
                gitHead: "88090ac",
                gitDirty: false,
                buildConfiguration: "Debug"
            ),
            determinism: TrainingRunManifest.DeterminismStamp(
                mlxGlobalSeed: 7,
                noiseSeedSalt: 11,
                tier: tier
            ),
            host: TrainingRunManifest.HostIdentity(
                hostName: "test-host",
                osVersion: "26.0",
                processIdentifier: processIdentifier
            ),
            launch: TrainingRunManifest.LaunchRecord(
                executablePath: "/usr/bin/kuyu",
                arguments: ["train", "attitude"],
                environmentOverrides: ["KUYU_MLX_RUN_REAL_ROBOT_PPO": "1"]
            )
        )
    }

    private func makeRecord(iteration: Int) -> TrainingRunIterationRecord {
        TrainingRunIterationRecord(
            iteration: iteration,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_100 + Double(iteration)),
            horizon: TrainingRunIterationRecord.HorizonState(
                supportHorizon: 512,
                frontierHorizon: 2048,
                fullHorizon: 6800,
                mode: "frontier"
            ),
            decision: TrainingRunIterationRecord.CandidateDecision(
                accepted: iteration % 2 == 0,
                rejectionReasons: iteration % 2 == 0 ? [] : ["frontier-regression"],
                horizonHealth: ["support": 0.93, "frontier": 0.61]
            ),
            evaluation: TrainingRunIterationRecord.EvaluationRecord(
                evaluationHorizon: 6800,
                metrics: ["meanSurvival": 2291.0, "tiltRMS": 0.18]
            ),
            failureEpisodes: [
                TrainingRunIterationRecord.FailureEpisode(
                    scenario: "suite-3-impulse",
                    seed: 99,
                    terminalStep: 2291,
                    reason: "sustained-fall"
                ),
            ],
            phaseTimings: ["rollout": 41.5, "update": 12.25],
            environmentSample: ["motorTimeConstant": 0.021],
            checkpoint: TrainingRunIterationRecord.CheckpointReference(
                path: "checkpoints/iter-\(iteration).safetensors",
                sha256Digest: String(repeating: "a", count: 64)
            )
        )
    }

    // MARK: - Creation and manifest

    @Test func createWritesManifestJournalOutcomeAndControl() throws {
        let root = try makeTemporaryRunRoot()
        let manifest = makeManifest(runID: "run-create")
        let writer = try TrainingRunArchiveWriter.create(manifest: manifest, in: root)
        #expect(writer.nextIteration == 0)

        let reader = TrainingRunArchiveReader(runDirectory: writer.runDirectory)
        #expect(try reader.loadManifest() == manifest)
        let outcome = try reader.loadOutcome()
        #expect(outcome.status == .running)
        let journal = try reader.readJournal()
        #expect(journal.records.isEmpty)
        #expect(journal.truncatedTailBytes == 0)
        let controlDirectory = writer.runDirectory
            .appendingPathComponent(TrainingRunContractSchema.controlDirectoryName, isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: controlDirectory.path))
    }

    @Test func createRefusesDuplicateDirectory() throws {
        let root = try makeTemporaryRunRoot()
        let manifest = makeManifest(runID: "run-duplicate")
        _ = try TrainingRunArchiveWriter.create(manifest: manifest, in: root)
        #expect {
            try TrainingRunArchiveWriter.create(manifest: manifest, in: root)
        } throws: { error in
            guard case TrainingRunContractError.duplicateRunDirectory = error else {
                return false
            }
            return true
        }
    }

    @Test func manifestValidationRejectsInvalidTier() throws {
        let manifest = makeManifest(runID: "run-bad-tier", tier: 3)
        #expect {
            try manifest.validate()
        } throws: { error in
            guard case TrainingRunContractError.invalidManifest = error else {
                return false
            }
            return true
        }
    }

    @Test func loadManifestRejectsDirectoryNameMismatch() throws {
        let root = try makeTemporaryRunRoot()
        let manifest = makeManifest(runID: "run-original")
        let writer = try TrainingRunArchiveWriter.create(manifest: manifest, in: root)
        let renamed = root.appendingPathComponent("run-renamed", isDirectory: true)
        try FileManager.default.moveItem(at: writer.runDirectory, to: renamed)
        let reader = TrainingRunArchiveReader(runDirectory: renamed)
        #expect {
            try reader.loadManifest()
        } throws: { error in
            guard case TrainingRunContractError.corruptedFile = error else {
                return false
            }
            return true
        }
    }

    // MARK: - Journal

    @Test func journalAppendAndReadRoundtrip() throws {
        let root = try makeTemporaryRunRoot()
        var writer = try TrainingRunArchiveWriter.create(
            manifest: makeManifest(runID: "run-journal"),
            in: root
        )
        let records = (0..<3).map(makeRecord(iteration:))
        for record in records {
            try writer.appendIteration(record)
        }
        let reader = TrainingRunArchiveReader(runDirectory: writer.runDirectory)
        let journal = try reader.readJournal()
        #expect(journal.records == records)
        #expect(journal.truncatedTailBytes == 0)
    }

    @Test func journalRecordsAreSingleCompactLines() throws {
        let root = try makeTemporaryRunRoot()
        var writer = try TrainingRunArchiveWriter.create(
            manifest: makeManifest(runID: "run-lines"),
            in: root
        )
        try writer.appendIteration(makeRecord(iteration: 0))
        try writer.appendIteration(makeRecord(iteration: 1))
        let journalURL = writer.runDirectory
            .appendingPathComponent(TrainingRunContractSchema.journalFileName, isDirectory: false)
        let data = try Data(contentsOf: journalURL)
        let newlineCount = data.count(where: { $0 == 0x0A })
        #expect(newlineCount == 2)
        #expect(data.last == 0x0A)
    }

    @Test func appendRejectsNonMonotonicIteration() throws {
        let root = try makeTemporaryRunRoot()
        var writer = try TrainingRunArchiveWriter.create(
            manifest: makeManifest(runID: "run-monotonic"),
            in: root
        )
        try writer.appendIteration(makeRecord(iteration: 0))
        #expect {
            try writer.appendIteration(makeRecord(iteration: 2))
        } throws: { error in
            guard case TrainingRunContractError.nonMonotonicIteration(let expected, let found) = error else {
                return false
            }
            return expected == 1 && found == 2
        }
    }

    @Test func readerToleratesUnknownJournalFields() throws {
        let root = try makeTemporaryRunRoot()
        var writer = try TrainingRunArchiveWriter.create(
            manifest: makeManifest(runID: "run-unknown-fields"),
            in: root
        )
        try writer.appendIteration(makeRecord(iteration: 0))
        let journalURL = writer.runDirectory
            .appendingPathComponent(TrainingRunContractSchema.journalFileName, isDirectory: false)
        let futureLine = """
        {"iteration":1,"recordedAt":"2026-06-12T00:00:00Z","futureField":{"nested":true},"failureEpisodes":[],"phaseTimings":{},"environmentSample":{}}
        """
        let handle = try FileHandle(forWritingTo: journalURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((futureLine + "\n").utf8))
        try handle.close()

        let reader = TrainingRunArchiveReader(runDirectory: writer.runDirectory)
        let journal = try reader.readJournal()
        #expect(journal.records.count == 2)
        #expect(journal.records[1].iteration == 1)
    }

    @Test func readerReportsTornTailWithoutDroppingRecords() throws {
        let root = try makeTemporaryRunRoot()
        var writer = try TrainingRunArchiveWriter.create(
            manifest: makeManifest(runID: "run-torn-tail"),
            in: root
        )
        try writer.appendIteration(makeRecord(iteration: 0))
        let journalURL = writer.runDirectory
            .appendingPathComponent(TrainingRunContractSchema.journalFileName, isDirectory: false)
        let handle = try FileHandle(forWritingTo: journalURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"iteration\":1,\"partial".utf8))
        try handle.close()

        let reader = TrainingRunArchiveReader(runDirectory: writer.runDirectory)
        let journal = try reader.readJournal()
        #expect(journal.records.count == 1)
        #expect(journal.truncatedTailBytes == "{\"iteration\":1,\"partial".utf8.count)
    }

    @Test func readerThrowsOnCorruptedMiddleLine() throws {
        let root = try makeTemporaryRunRoot()
        var writer = try TrainingRunArchiveWriter.create(
            manifest: makeManifest(runID: "run-corrupt-middle"),
            in: root
        )
        try writer.appendIteration(makeRecord(iteration: 0))
        let journalURL = writer.runDirectory
            .appendingPathComponent(TrainingRunContractSchema.journalFileName, isDirectory: false)
        let handle = try FileHandle(forWritingTo: journalURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("not-json\n".utf8))
        try handle.close()
        var tail = try TrainingRunContractCodec.makeJournalEncoder().encode(makeRecord(iteration: 1))
        tail.append(0x0A)
        let appendHandle = try FileHandle(forWritingTo: journalURL)
        try appendHandle.seekToEnd()
        try appendHandle.write(contentsOf: tail)
        try appendHandle.close()

        let reader = TrainingRunArchiveReader(runDirectory: writer.runDirectory)
        #expect {
            try reader.readJournal()
        } throws: { error in
            guard case TrainingRunContractError.corruptedJournalLine(let lineNumber, _, _) = error else {
                return false
            }
            return lineNumber == 2
        }
    }

    // MARK: - Resume

    @Test func openContinuesIterationNumbering() throws {
        let root = try makeTemporaryRunRoot()
        let manifest = makeManifest(runID: "run-resume")
        var writer = try TrainingRunArchiveWriter.create(manifest: manifest, in: root)
        try writer.appendIteration(makeRecord(iteration: 0))
        try writer.appendIteration(makeRecord(iteration: 1))

        var reopened = try TrainingRunArchiveWriter.open(runID: manifest.runID, in: root)
        #expect(reopened.nextIteration == 2)
        #expect(reopened.repairedTailByteCount == nil)
        try reopened.appendIteration(makeRecord(iteration: 2))
        let reader = TrainingRunArchiveReader(runDirectory: reopened.runDirectory)
        #expect(try reader.readJournal().records.count == 3)
    }

    @Test func openRefusesTornTailUnlessRepairRequested() throws {
        let root = try makeTemporaryRunRoot()
        let manifest = makeManifest(runID: "run-repair")
        var writer = try TrainingRunArchiveWriter.create(manifest: manifest, in: root)
        try writer.appendIteration(makeRecord(iteration: 0))
        let journalURL = writer.runDirectory
            .appendingPathComponent(TrainingRunContractSchema.journalFileName, isDirectory: false)
        let handle = try FileHandle(forWritingTo: journalURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"torn".utf8))
        try handle.close()

        #expect {
            try TrainingRunArchiveWriter.open(runID: manifest.runID, in: root)
        } throws: { error in
            guard case TrainingRunContractError.tornJournalTail(let byteCount, _) = error else {
                return false
            }
            return byteCount == "{\"torn".utf8.count
        }

        var repaired = try TrainingRunArchiveWriter.open(
            runID: manifest.runID,
            in: root,
            repairingTornTail: true
        )
        #expect(repaired.repairedTailByteCount == "{\"torn".utf8.count)
        #expect(repaired.nextIteration == 1)
        try repaired.appendIteration(makeRecord(iteration: 1))
        let reader = TrainingRunArchiveReader(runDirectory: repaired.runDirectory)
        let journal = try reader.readJournal()
        #expect(journal.records.count == 2)
        #expect(journal.truncatedTailBytes == 0)
    }

    @Test func openRefusesWhileAnotherWriterProcessIsAlive() throws {
        let root = try makeTemporaryRunRoot()
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["30"]
        try sleeper.run()
        defer {
            sleeper.terminate()
            sleeper.waitUntilExit()
        }
        let manifest = makeManifest(
            runID: "run-live-writer",
            processIdentifier: sleeper.processIdentifier
        )
        _ = try TrainingRunArchiveWriter.create(manifest: manifest, in: root)
        #expect {
            try TrainingRunArchiveWriter.open(runID: manifest.runID, in: root)
        } throws: { error in
            guard case TrainingRunContractError.runStillLive(let processIdentifier) = error else {
                return false
            }
            return processIdentifier == sleeper.processIdentifier
        }
    }

    // MARK: - Heartbeat, outcome, liveness

    @Test func heartbeatRoundtrip() throws {
        let root = try makeTemporaryRunRoot()
        let writer = try TrainingRunArchiveWriter.create(
            manifest: makeManifest(runID: "run-heartbeat"),
            in: root
        )
        let reader = TrainingRunArchiveReader(runDirectory: writer.runDirectory)
        #expect(try reader.loadHeartbeat() == nil)
        let heartbeat = TrainingRunHeartbeat(
            updatedAt: Date(timeIntervalSince1970: 1_700_000_200),
            iteration: 5,
            phase: "rollout",
            processIdentifier: ProcessInfo.processInfo.processIdentifier
        )
        try writer.writeHeartbeat(heartbeat)
        #expect(try reader.loadHeartbeat() == heartbeat)
    }

    @Test func failedOutcomeRequiresReason() throws {
        let root = try makeTemporaryRunRoot()
        let writer = try TrainingRunArchiveWriter.create(
            manifest: makeManifest(runID: "run-outcome"),
            in: root
        )
        #expect {
            try writer.writeOutcome(
                TrainingRunOutcome(status: .failed, updatedAt: Date(timeIntervalSince1970: 1_700_000_300))
            )
        } throws: { error in
            guard case TrainingRunContractError.invalidOutcome = error else {
                return false
            }
            return true
        }
        try writer.writeOutcome(
            TrainingRunOutcome(
                status: .failed,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_300),
                finalIteration: 9,
                failureReason: "diverged: non-finite loss"
            )
        )
        let reader = TrainingRunArchiveReader(runDirectory: writer.runDirectory)
        #expect(try reader.loadOutcome().failureReason == "diverged: non-finite loss")
        #expect(try reader.liveness() == .finished(.failed))
    }

    @Test func livenessReportsLiveForCurrentProcess() throws {
        let root = try makeTemporaryRunRoot()
        let writer = try TrainingRunArchiveWriter.create(
            manifest: makeManifest(runID: "run-live"),
            in: root
        )
        let reader = TrainingRunArchiveReader(runDirectory: writer.runDirectory)
        #expect(try reader.liveness() == .live(
            processIdentifier: ProcessInfo.processInfo.processIdentifier
        ))
    }

    @Test func livenessDerivesInterruptedFromDeadWriter() throws {
        let root = try makeTemporaryRunRoot()
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try probe.run()
        probe.waitUntilExit()
        let deadProcessIdentifier = probe.processIdentifier

        let writer = try TrainingRunArchiveWriter.create(
            manifest: makeManifest(runID: "run-interrupted", processIdentifier: deadProcessIdentifier),
            in: root
        )
        let heartbeat = TrainingRunHeartbeat(
            updatedAt: Date(timeIntervalSince1970: 1_700_000_400),
            iteration: 12,
            phase: "update",
            processIdentifier: deadProcessIdentifier
        )
        try writer.writeHeartbeat(heartbeat)
        let reader = TrainingRunArchiveReader(runDirectory: writer.runDirectory)
        #expect(try reader.liveness() == .interrupted(lastHeartbeat: heartbeat))
    }

    // MARK: - Control plane

    @Test func controlRequestAndAcknowledgmentFlow() throws {
        let root = try makeTemporaryRunRoot()
        let writer = try TrainingRunArchiveWriter.create(
            manifest: makeManifest(runID: "run-control"),
            in: root
        )
        let reader = TrainingRunArchiveReader(runDirectory: writer.runDirectory)
        #expect(try writer.pendingControlCommand() == nil)
        #expect(try reader.latestControlSequence() == nil)

        let command = TrainingRunControlCommand(
            sequence: 1,
            action: .pause,
            requestedAt: Date(timeIntervalSince1970: 1_700_000_500),
            requestedBy: "kuyu-cli"
        )
        try reader.submitControlCommand(command)
        #expect(try writer.pendingControlCommand() == command)
        #expect(try reader.latestControlSequence() == 1)

        let acknowledgment = TrainingRunControlAcknowledgment(
            sequence: 1,
            command: command.command,
            appliedAt: Date(timeIntervalSince1970: 1_700_000_501),
            iteration: 7
        )
        try writer.acknowledgeControlCommand(acknowledgment)
        #expect(try writer.pendingControlCommand() == nil)
        #expect(try reader.controlAcknowledgment(sequence: 1) == acknowledgment)
        #expect(try reader.latestControlSequence() == 1)
    }

    @Test func submitRefusesSecondPendingCommand() throws {
        let root = try makeTemporaryRunRoot()
        let writer = try TrainingRunArchiveWriter.create(
            manifest: makeManifest(runID: "run-control-pending"),
            in: root
        )
        let reader = TrainingRunArchiveReader(runDirectory: writer.runDirectory)
        try reader.submitControlCommand(TrainingRunControlCommand(
            sequence: 1,
            action: .pause,
            requestedAt: Date(timeIntervalSince1970: 1_700_000_600),
            requestedBy: "kuyu-cli"
        ))
        #expect {
            try reader.submitControlCommand(TrainingRunControlCommand(
                sequence: 2,
                action: .stop,
                requestedAt: Date(timeIntervalSince1970: 1_700_000_601),
                requestedBy: "bounded-ui"
            ))
        } throws: { error in
            guard case TrainingRunContractError.pendingControlCommandExists(let sequence) = error else {
                return false
            }
            return sequence == 1
        }
    }

    @Test func submitRefusesStaleSequence() throws {
        let root = try makeTemporaryRunRoot()
        let writer = try TrainingRunArchiveWriter.create(
            manifest: makeManifest(runID: "run-control-stale"),
            in: root
        )
        let reader = TrainingRunArchiveReader(runDirectory: writer.runDirectory)
        try reader.submitControlCommand(TrainingRunControlCommand(
            sequence: 3,
            action: .checkpoint,
            requestedAt: Date(timeIntervalSince1970: 1_700_000_700),
            requestedBy: "kuyu-cli"
        ))
        try writer.acknowledgeControlCommand(TrainingRunControlAcknowledgment(
            sequence: 3,
            command: TrainingRunControlAction.checkpoint.rawValue,
            appliedAt: Date(timeIntervalSince1970: 1_700_000_701),
            iteration: 2
        ))
        #expect {
            try reader.submitControlCommand(TrainingRunControlCommand(
                sequence: 3,
                action: .stop,
                requestedAt: Date(timeIntervalSince1970: 1_700_000_702),
                requestedBy: "kuyu-cli"
            ))
        } throws: { error in
            guard case TrainingRunContractError.staleControlSequence(let latest, let found) = error else {
                return false
            }
            return latest == 3 && found == 3
        }
    }

    @Test func unknownControlCommandIsDecodableAndRejectable() throws {
        let root = try makeTemporaryRunRoot()
        let writer = try TrainingRunArchiveWriter.create(
            manifest: makeManifest(runID: "run-control-unknown"),
            in: root
        )
        let reader = TrainingRunArchiveReader(runDirectory: writer.runDirectory)
        try reader.submitControlCommand(TrainingRunControlCommand(
            sequence: 1,
            command: "warp-speed",
            requestedAt: Date(timeIntervalSince1970: 1_700_000_800),
            requestedBy: "kuyu-cli"
        ))
        let pending = try #require(try writer.pendingControlCommand())
        #expect(pending.action == nil)
        #expect {
            try writer.acknowledgeControlCommand(TrainingRunControlAcknowledgment(
                sequence: 1,
                command: pending.command,
                appliedAt: Date(timeIntervalSince1970: 1_700_000_801),
                iteration: 0,
                rejected: true
            ))
        } throws: { error in
            guard case TrainingRunContractError.invalidControlRecord = error else {
                return false
            }
            return true
        }
        try writer.acknowledgeControlCommand(TrainingRunControlAcknowledgment(
            sequence: 1,
            command: pending.command,
            appliedAt: Date(timeIntervalSince1970: 1_700_000_801),
            iteration: 0,
            rejected: true,
            reason: "unknown command"
        ))
        let acknowledgment = try #require(try reader.controlAcknowledgment(sequence: 1))
        #expect(acknowledgment.rejected)
    }

    // MARK: - Registry and run root

    @Test func registryListsReadableAndUnreadableEntries() throws {
        let root = try makeTemporaryRunRoot()
        let older = makeManifest(
            runID: "run-older",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let newer = makeManifest(
            runID: "run-newer",
            createdAt: Date(timeIntervalSince1970: 1_700_100_000)
        )
        _ = try TrainingRunArchiveWriter.create(manifest: older, in: root)
        _ = try TrainingRunArchiveWriter.create(manifest: newer, in: root)
        let strayDirectory = root.appendingPathComponent("not-a-run", isDirectory: true)
        try FileManager.default.createDirectory(at: strayDirectory, withIntermediateDirectories: false)

        let registry = TrainingRunArchiveRegistry(runRoot: root)
        let entries = try registry.list()
        #expect(entries.count == 3)
        #expect(entries[0].manifest?.runID == newer.runID)
        #expect(entries[1].manifest?.runID == older.runID)
        #expect(entries[2].manifest == nil)
        #expect(entries[2].directory.lastPathComponent == "not-a-run")
    }

    @Test func registryReturnsEmptyForMissingRoot() throws {
        let registry = TrainingRunArchiveRegistry(
            runRoot: FileManager.default.temporaryDirectory
                .appendingPathComponent("kuyu-run-contract-missing-\(UUID().uuidString)", isDirectory: true)
        )
        #expect(try registry.list().isEmpty)
    }

    @Test func resolveRunRootHonorsOverrideAndRejectsRelativePath() throws {
        let resolved = try TrainingRunContractSchema.resolveRunRoot(
            environment: [TrainingRunContractSchema.runRootEnvironmentKey: "/var/kuyu/runs"]
        )
        #expect(resolved.path == "/var/kuyu/runs")
        #expect {
            try TrainingRunContractSchema.resolveRunRoot(
                environment: [TrainingRunContractSchema.runRootEnvironmentKey: "relative/runs"]
            )
        } throws: { error in
            guard case TrainingRunContractError.invalidRunRoot = error else {
                return false
            }
            return true
        }
        let defaultRoot = try TrainingRunContractSchema.resolveRunRoot(environment: [:])
        #expect(defaultRoot.path.hasSuffix(".kuyu/runs"))
    }
}
