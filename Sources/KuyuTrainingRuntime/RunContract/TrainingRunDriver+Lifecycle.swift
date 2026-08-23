import Foundation
import KuyuTrainingContracts

public extension TrainingRunDriver {
    /// Starts a new run directory under `runRoot`.
    ///
    /// `repositoryDirectory` anchors the recorded code identity: `git
    /// rev-parse HEAD` and the dirty check run against the repository that
    /// contains it. Callers pass the directory of the code under training —
    /// a missing or non-git directory is a typed error, never a silent skip.
    static func begin(
        task: String,
        profile: String,
        semanticVersion: String,
        cacheKey: String,
        randomSeedBase: UInt64,
        randomnessContractID: String,
        noiseSeedSalt: UInt64?,
        determinismTier: Int,
        runRoot: URL,
        repositoryDirectory: URL
    ) throws -> TrainingRunDriver {
        let runID = generateRunID(task: task)
        let code = try resolveCodeIdentity(repositoryDirectory: repositoryDirectory)
        let manifest = TrainingRunManifest(
            runID: TrainingRunID(runID),
            createdAt: Date(),
            task: task,
            profile: profile,
            semanticVersion: semanticVersion,
            cacheKey: cacheKey,
            code: code,
            determinism: TrainingRunManifest.DeterminismStamp(
                randomSeedBase: randomSeedBase,
                randomnessContractID: randomnessContractID,
                noiseSeedSalt: noiseSeedSalt,
                tier: determinismTier
            ),
            host: TrainingRunManifest.HostIdentity(
                hostName: ProcessInfo.processInfo.hostName,
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                processIdentifier: ProcessInfo.processInfo.processIdentifier
            ),
            launch: TrainingRunManifest.LaunchRecord(
                executablePath: CommandLine.arguments.first ?? "unknown",
                arguments: Array(CommandLine.arguments.dropFirst()),
                environmentOverrides: relevantEnvironmentOverrides()
            )
        )
        let writer = try TrainingRunArchiveWriter.create(manifest: manifest, in: runRoot)
        return TrainingRunDriver(writer: writer)
    }

    static func resume(runID: String, runRoot: URL) throws -> TrainingRunDriver {
        let writer = try TrainingRunArchiveWriter.open(
            runID: TrainingRunID(runID),
            in: runRoot,
            repairingTornTail: true
        )
        if let repaired = writer.repairedTailByteCount, repaired > 0 {
            print("TRAINING-RUN resume repaired torn journal tail (\(repaired) bytes) run=\(runID)")
        }
        return TrainingRunDriver(writer: writer)
    }

    /// Appends an iteration record, skipping records the journal already
    /// holds (crash-window redo under Tier-0 determinism reproduces them
    /// bit-identically, so skipping is sound).
    func recordIteration(_ record: TrainingRunIterationRecord) throws {
        if record.iteration < writer.nextIteration {
            print("TRAINING-RUN journal already contains iteration \(record.iteration) (skip)")
            return
        }
        try writer.appendIteration(record)
    }

    func writeHeartbeat(iteration: Int, phase: String) throws {
        try writer.writeHeartbeat(
            TrainingRunHeartbeat(
                updatedAt: Date(),
                iteration: iteration,
                phase: phase,
                processIdentifier: ProcessInfo.processInfo.processIdentifier
            )
        )
    }
}
