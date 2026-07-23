import Foundation
import Testing
@testable import KuyuTraining
@testable import KuyuTrainingRuntime

private func makeControlTestRunRoot(label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-driver-control-\(label)-\(UUID().uuidString)", isDirectory: true)
}

private func removeControlTestRunRoot(_ runRoot: URL) {
    guard FileManager.default.fileExists(atPath: runRoot.path) else {
        return
    }
    do {
        try FileManager.default.removeItem(at: runRoot)
    } catch {
        Issue.record("Failed to remove temporary run root \(runRoot.path): \(error)")
    }
}

private func beginControlTestRecorder(runRoot: URL) throws -> TrainingRunDriver {
    let runID = TrainingRunID("control-test-\(UUID().uuidString)")
    let manifest = TrainingRunManifest(
        runID: runID,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        task: "control-test",
        profile: "P1",
        semanticVersion: "control-test-v1",
        cacheKey: "control-test-cache-v1",
        code: TrainingRunManifest.CodeIdentity(
            gitHead: "control-test-head",
            gitDirty: false,
            buildConfiguration: "debug"
        ),
        determinism: TrainingRunManifest.DeterminismStamp(
            mlxRandomSeedBase: 0,
            mlxRandomnessContractID: "test-task-local-rng-v1",
            noiseSeedSalt: nil,
            tier: 0
        ),
        host: TrainingRunManifest.HostIdentity(
            hostName: "control-test-host",
            osVersion: "test",
            processIdentifier: ProcessInfo.processInfo.processIdentifier
        ),
        launch: TrainingRunManifest.LaunchRecord(
            executablePath: "/usr/bin/kuyu-control-test",
            arguments: [],
            environmentOverrides: [:]
        )
    )
    let writer = try TrainingRunArchiveWriter.create(manifest: manifest, in: runRoot)
    return TrainingRunDriver(writer: writer)
}

private func writeControlCommand(
    sequence: Int,
    command: String,
    runDirectory: URL
) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let payload = TrainingRunControlCommand(
        sequence: sequence,
        command: command,
        requestedAt: Date(),
        requestedBy: "control-test"
    )
    let url = runDirectory
        .appendingPathComponent(TrainingRunContractSchema.controlDirectoryName, isDirectory: true)
        .appendingPathComponent(TrainingRunContractSchema.controlCommandFileName, isDirectory: false)
    try encoder.encode(payload).write(to: url, options: .atomic)
}

private func readControlAcknowledgment(
    sequence: Int,
    runDirectory: URL
) throws -> TrainingRunControlAcknowledgment {
    let url = runDirectory
        .appendingPathComponent(TrainingRunContractSchema.controlDirectoryName, isDirectory: true)
        .appendingPathComponent(
            TrainingRunContractSchema.controlAckFileName(sequence: sequence),
            isDirectory: false
        )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(TrainingRunControlAcknowledgment.self, from: Data(contentsOf: url))
}

private func readOutcomeStatus(runDirectory: URL) throws -> TrainingRunLifecycleStatus {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let outcome = try decoder.decode(
        TrainingRunOutcome.self,
        from: Data(contentsOf: runDirectory.appendingPathComponent("outcome.json"))
    )
    return outcome.status
}

private func waitForOutcomeStatus(
    _ expected: TrainingRunLifecycleStatus,
    runDirectory: URL,
    timeout: Duration = .seconds(10)
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if try readOutcomeStatus(runDirectory: runDirectory) == expected {
            return
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    Issue.record("Timed out waiting for outcome status \(expected) in \(runDirectory.path)")
}

private func pendingCommandExists(runDirectory: URL) -> Bool {
    let url = runDirectory
        .appendingPathComponent(TrainingRunContractSchema.controlDirectoryName, isDirectory: true)
        .appendingPathComponent(TrainingRunContractSchema.controlCommandFileName, isDirectory: false)
    return FileManager.default.fileExists(atPath: url.path)
}

@Test(.timeLimit(.minutes(1)))
func trainingRunDriverStopCommandStopsRunThenWritesAck() async throws {
    let runRoot = makeControlTestRunRoot(label: "stop")
    defer { removeControlTestRunRoot(runRoot) }

    let recorder = try beginControlTestRecorder(runRoot: runRoot)
    let runDirectory = URL(fileURLWithPath: recorder.runDirectoryPath, isDirectory: true)

    try writeControlCommand(sequence: 1, command: "stop", runDirectory: runDirectory)
    let directive = try await recorder.applyPendingControl(iteration: 5)
    #expect(directive == .stopRun)

    let ack = try readControlAcknowledgment(sequence: 1, runDirectory: runDirectory)
    #expect(ack.command == "stop")
    #expect(ack.iteration == 5)
    #expect(!ack.rejected)
    #expect(!pendingCommandExists(runDirectory: runDirectory))

    try recorder.finishCancelled(acceptedCheckpointPath: nil)
    #expect(try readOutcomeStatus(runDirectory: runDirectory) == .cancelled)
}

@Test(.timeLimit(.minutes(1)))
func trainingRunDriverRejectsInapplicableCommandsWithReasons() async throws {
    let runRoot = makeControlTestRunRoot(label: "reject")
    defer { removeControlTestRunRoot(runRoot) }

    let recorder = try beginControlTestRecorder(runRoot: runRoot)
    let runDirectory = URL(fileURLWithPath: recorder.runDirectoryPath, isDirectory: true)

    try writeControlCommand(sequence: 1, command: "self-destruct", runDirectory: runDirectory)
    #expect(try await recorder.applyPendingControl(iteration: 2) == .continueRun)
    let unknownAck = try readControlAcknowledgment(sequence: 1, runDirectory: runDirectory)
    #expect(unknownAck.rejected)
    #expect(unknownAck.reason?.contains("unknown command") == true)

    try writeControlCommand(sequence: 2, command: "resume", runDirectory: runDirectory)
    #expect(try await recorder.applyPendingControl(iteration: 2) == .continueRun)
    let resumeAck = try readControlAcknowledgment(sequence: 2, runDirectory: runDirectory)
    #expect(resumeAck.rejected)
    #expect(resumeAck.reason?.contains("not paused") == true)

    try writeControlCommand(sequence: 3, command: "checkpoint", runDirectory: runDirectory)
    #expect(try await recorder.applyPendingControl(iteration: 2) == .continueRun)
    let checkpointAck = try readControlAcknowledgment(sequence: 3, runDirectory: runDirectory)
    #expect(checkpointAck.rejected)
    #expect(checkpointAck.reason?.contains("checkpoint-on-demand") == true)
    #expect(!pendingCommandExists(runDirectory: runDirectory))
}

@Test(.timeLimit(.minutes(1)))
func trainingRunDriverPauseBlocksUntilResume() async throws {
    let runRoot = makeControlTestRunRoot(label: "pause-resume")
    defer { removeControlTestRunRoot(runRoot) }

    let recorder = try beginControlTestRecorder(runRoot: runRoot)
    let runDirectory = URL(fileURLWithPath: recorder.runDirectoryPath, isDirectory: true)

    try writeControlCommand(sequence: 1, command: "pause", runDirectory: runDirectory)
    let resumeWriter = Task {
        try await waitForOutcomeStatus(.paused, runDirectory: runDirectory)
        try writeControlCommand(sequence: 2, command: "resume", runDirectory: runDirectory)
    }

    let directive = try await recorder.applyPendingControl(iteration: 9)
    try await resumeWriter.value
    #expect(directive == .continueRun)
    #expect(try readOutcomeStatus(runDirectory: runDirectory) == .running)

    let pauseAck = try readControlAcknowledgment(sequence: 1, runDirectory: runDirectory)
    #expect(!pauseAck.rejected)
    let resumeAck = try readControlAcknowledgment(sequence: 2, runDirectory: runDirectory)
    #expect(!resumeAck.rejected)
    #expect(!pendingCommandExists(runDirectory: runDirectory))
}

@Test(.timeLimit(.minutes(1)))
func trainingRunDriverStopWhilePausedCancelsRun() async throws {
    let runRoot = makeControlTestRunRoot(label: "pause-stop")
    defer { removeControlTestRunRoot(runRoot) }

    let recorder = try beginControlTestRecorder(runRoot: runRoot)
    let runDirectory = URL(fileURLWithPath: recorder.runDirectoryPath, isDirectory: true)

    try writeControlCommand(sequence: 1, command: "pause", runDirectory: runDirectory)
    let stopWriter = Task {
        try await waitForOutcomeStatus(.paused, runDirectory: runDirectory)
        try writeControlCommand(sequence: 2, command: "stop", runDirectory: runDirectory)
    }

    let directive = try await recorder.applyPendingControl(iteration: 4)
    try await stopWriter.value
    #expect(directive == .stopRun)

    let stopAck = try readControlAcknowledgment(sequence: 2, runDirectory: runDirectory)
    #expect(!stopAck.rejected)
    #expect(stopAck.command == "stop")

    try recorder.finishCancelled(acceptedCheckpointPath: nil)
    #expect(try readOutcomeStatus(runDirectory: runDirectory) == .cancelled)
}
