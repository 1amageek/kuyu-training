import Foundation
import Synchronization
import Testing
@testable import KuyuTraining

// MARK: - Deterministic fakes

/// Stateless backend producing a deterministic population purely from
/// (generationIndex, candidate index, parents, seed) so a resumed run can be
/// compared bit-for-bit against an uninterrupted one.
private struct ResumeFakeBackend: EvolutionaryTrainingBackend {
    func seedPopulation(request: EvolutionSeedRequest) async throws -> EvolutionPopulation {
        population(
            config: request.config,
            generationIndex: 0,
            parents: [],
            mutationRate: request.mutationRate,
            mutationNoiseScale: request.mutationNoiseScale,
            commonRandomSeed: request.commonRandomSeed
        )
    }

    func produceNextGeneration(request: EvolutionGenerationRequest) async throws -> EvolutionPopulation {
        population(
            config: request.config,
            generationIndex: request.previousPopulation.generationIndex + 1,
            parents: request.parentCandidateIDs,
            mutationRate: request.mutationRate,
            mutationNoiseScale: request.mutationNoiseScale,
            commonRandomSeed: request.commonRandomSeed
        )
    }

    private func population(
        config: EvolutionRunConfig,
        generationIndex: Int,
        parents: [String],
        mutationRate: Double,
        mutationNoiseScale: Double,
        commonRandomSeed: UInt64
    ) -> EvolutionPopulation {
        EvolutionPopulation(
            runID: config.runID,
            generationIndex: generationIndex,
            candidates: (0..<config.populationSize).map { index in
                let isIncumbent = generationIndex == 0 && index == 0
                return GenomeCandidate(
                    runID: config.runID,
                    generationIndex: generationIndex,
                    candidateID: "g\(generationIndex)-c\(index)",
                    genomeID: "genome-g\(generationIndex)-c\(index)",
                    parentCandidateIDs: parents,
                    checkpointID: "checkpoint-g\(generationIndex)-c\(index)",
                    checkpointURL: URL(fileURLWithPath: "/tmp/checkpoint-g\(generationIndex)-c\(index)"),
                    mutationRate: isIncumbent ? 0 : mutationRate,
                    mutationNoiseScale: isIncumbent ? 0 : mutationNoiseScale,
                    commonRandomSeed: commonRandomSeed,
                    mutationSummary: isIncumbent ? "incumbent" : (generationIndex == 0 ? "seeded" : "mutated"),
                    isIncumbent: isIncumbent
                )
            }
        )
    }
}

/// Deterministic evaluator: fitness improves each generation so the run never
/// plateaus, and every candidate passes the task so the gate accepts.
private struct ResumeFakeEvaluator: EvolutionCandidateEvaluating {
    func evaluateCandidate(request: EvolutionCandidateEvaluationRequest) async throws -> FitnessSummary {
        let rank = Double(Int(request.candidate.candidateID.split(separator: "c").last ?? "0") ?? 0)
        let generationOffset = Double(request.candidate.generationIndex) * 100
        let fitness = generationOffset + rank
        return FitnessSummary(
            runID: request.config.runID,
            generationIndex: request.candidate.generationIndex,
            candidateID: request.candidate.candidateID,
            taskID: request.config.taskID,
            scalarFitness: fitness,
            rewardAverage: fitness,
            taskPassRate: 1.0,
            safetyViolationRate: 0,
            holdTimeRatio: 1.0,
            energyPenalty: 0.1,
            workerThroughput: Double(request.workerCount)
        )
    }
}

// MARK: - Helpers

private func resumeConfig(runID: String, generationCount: Int) -> EvolutionRunConfig {
    EvolutionRunConfig(
        runID: runID,
        taskID: "lift",
        configHash: "resume-config-hash",
        policyID: "manasMLX",
        populationSize: 4,
        generationCount: generationCount,
        eliteCount: 2,
        workerCount: 1,
        commonRandomSeed: 7,
        mutationRate: 0.1,
        mutationNoiseScale: 0.02,
        earlyStopping: EvolutionEarlyStoppingConfig(enabled: false)
    )
}

private func resumeGatePolicy() -> EvolutionGatePolicy {
    EvolutionGatePolicy(
        eliteCount: 2,
        minimumTaskPassRate: 0,
        maximumSafetyViolationRate: 1,
        minimumHoldTimeRatio: 0
    )
}

private func resumeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-resume-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private func sortedCandidates(_ candidates: [GenomeCandidate]) -> [GenomeCandidate] {
    candidates.sorted { ($0.generationIndex, $0.candidateID) < ($1.generationIndex, $1.candidateID) }
}

private func sortedFitness(_ fitness: [FitnessSummary]) -> [FitnessSummary] {
    fitness.sorted { ($0.generationIndex, $0.candidateID) < ($1.generationIndex, $1.candidateID) }
}

/// Runs `generationCount` generations, stopping cooperatively once `stopAfter`
/// generations have completed (nil = run to completion).
private func runCampaign(
    runID: String,
    generationCount: Int,
    directory: URL,
    resumeFrom: EvolutionResumeState? = nil,
    stopAfterCompletedGenerations stopAfter: Int? = nil
) async -> EvolutionRunResult {
    let orchestrator = EvolutionRunOrchestrator(backend: ResumeFakeBackend(), evaluator: ResumeFakeEvaluator())
    let completed = Mutex(0)
    let stopRequested: @Sendable () -> Bool = {
        guard let stopAfter else { return false }
        return completed.withLock { $0 >= stopAfter }
    }
    let onEvent: @Sendable (EvolutionRunEvent) -> Void = { event in
        if case .generationCompleted = event {
            completed.withLock { $0 += 1 }
        }
    }
    return await orchestrator.run(
        config: resumeConfig(runID: runID, generationCount: generationCount),
        gatePolicy: resumeGatePolicy(),
        artifactDirectory: directory,
        resumeFrom: resumeFrom,
        stopRequested: stopRequested,
        onEvent: onEvent
    )
}

// MARK: - T1: Tier-0 equivalence

@Test func resumeProducesBitIdenticalCandidatesAndFitness() async throws {
    let canonicalDir = try resumeTemporaryDirectory()
    let resumeDir = try resumeTemporaryDirectory()
    defer { cleanup(canonicalDir); cleanup(resumeDir) }

    // Canonical: 6 generations, uninterrupted.
    let canonical = await runCampaign(runID: "resume-eq", generationCount: 6, directory: canonicalDir)
    #expect(canonical.manifest.terminalState == .completed)
    #expect(canonical.generations.count == 6)

    // Interrupted: same run id/config, stop after 3 generations complete.
    let interrupted = await runCampaign(
        runID: "resume-eq",
        generationCount: 6,
        directory: resumeDir,
        stopAfterCompletedGenerations: 3
    )
    #expect(interrupted.manifest.terminalState == .paused)

    // The last committed generation is the highest with a durable checkpoint.
    let store = EvolutionResumeCheckpointStore()
    let highest = try #require(try store.highestCommittedGeneration(in: resumeDir, expectedConfigHash: "resume-config-hash"))
    #expect(highest == 2)

    // Resume in place and run to completion.
    let resumeState = try store.loadResumeState(
        in: resumeDir,
        upToGeneration: highest,
        expectedConfigHash: "resume-config-hash"
    )
    #expect(resumeState.startGenerationIndex == 3)
    let resumed = await runCampaign(
        runID: "resume-eq",
        generationCount: 6,
        directory: resumeDir,
        resumeFrom: resumeState
    )
    #expect(resumed.manifest.terminalState == .completed)

    // Acceptance line: resumed run is bit-identical to the uninterrupted run.
    #expect(resumed.candidates.count == canonical.candidates.count)
    #expect(resumed.fitness.count == canonical.fitness.count)
    #expect(sortedCandidates(resumed.candidates) == sortedCandidates(canonical.candidates))
    #expect(sortedFitness(resumed.fitness) == sortedFitness(canonical.fitness))
}

// MARK: - T2: crash recovery (discard in-flight generation)

@Test func resumeStateRestoresNextPopulationForDiscardedGeneration() async throws {
    let canonicalDir = try resumeTemporaryDirectory()
    let resumeDir = try resumeTemporaryDirectory()
    defer { cleanup(canonicalDir); cleanup(resumeDir) }

    let canonical = await runCampaign(runID: "resume-crash", generationCount: 5, directory: canonicalDir)
    _ = await runCampaign(
        runID: "resume-crash",
        generationCount: 5,
        directory: resumeDir,
        stopAfterCompletedGenerations: 2
    )

    let store = EvolutionResumeCheckpointStore()
    #expect(try store.committedGenerations(in: resumeDir) == [0, 1])
    let resumeState = try store.loadResumeState(in: resumeDir, upToGeneration: 1)

    // The population to re-run at generation 2 matches the canonical generation-2
    // population, so the discarded in-flight generation is recomputed identically.
    let canonicalGen2 = sortedCandidates(canonical.candidates.filter { $0.generationIndex == 2 })
    let restoredGen2 = sortedCandidates(resumeState.currentPopulation.candidates)
    #expect(resumeState.currentPopulation.generationIndex == 2)
    #expect(restoredGen2 == canonicalGen2)

    let resumed = await runCampaign(
        runID: "resume-crash",
        generationCount: 5,
        directory: resumeDir,
        resumeFrom: resumeState
    )
    #expect(sortedFitness(resumed.fitness) == sortedFitness(canonical.fitness))
}

// MARK: - T3: fail-closed integrity

@Test func corruptCheckpointFailsClosed() async throws {
    let directory = try resumeTemporaryDirectory()
    defer { cleanup(directory) }
    _ = await runCampaign(
        runID: "resume-corrupt",
        generationCount: 5,
        directory: directory,
        stopAfterCompletedGenerations: 3
    )
    let store = EvolutionResumeCheckpointStore()
    let corrupt = store.resumeDirectory(in: directory)
        .appendingPathComponent("generation-2.json", isDirectory: false)
    try Data("{ not valid json".utf8).write(to: corrupt)

    #expect(throws: EvolutionResumeCheckpointStore.StoreError.self) {
        _ = try store.committedGenerations(in: directory)
    }
}

@Test func missingMiddleCheckpointFailsClosed() async throws {
    let directory = try resumeTemporaryDirectory()
    defer { cleanup(directory) }
    _ = await runCampaign(
        runID: "resume-gap",
        generationCount: 5,
        directory: directory,
        stopAfterCompletedGenerations: 3
    )
    let store = EvolutionResumeCheckpointStore()
    let middle = store.resumeDirectory(in: directory)
        .appendingPathComponent("generation-1.json", isDirectory: false)
    try FileManager.default.removeItem(at: middle)

    #expect(throws: EvolutionResumeCheckpointStore.StoreError.self) {
        _ = try store.loadResumeState(in: directory, upToGeneration: 2)
    }
}

@Test func configHashMismatchFailsClosed() async throws {
    let directory = try resumeTemporaryDirectory()
    defer { cleanup(directory) }
    _ = await runCampaign(
        runID: "resume-hash",
        generationCount: 5,
        directory: directory,
        stopAfterCompletedGenerations: 3
    )
    let store = EvolutionResumeCheckpointStore()
    #expect(throws: EvolutionResumeCheckpointStore.StoreError.self) {
        _ = try store.loadResumeState(in: directory, upToGeneration: 2, expectedConfigHash: "different-hash")
    }
}
