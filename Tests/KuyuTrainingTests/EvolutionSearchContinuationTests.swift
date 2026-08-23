import Foundation
import Synchronization
import Testing

@testable import KuyuTraining

// Behavioral coverage for search continuation below the gate: a bounded
// number of consecutive gate-rejected generations may keep exploring with
// ranking-selected parents, while the default budget preserves the
// historical stop-at-first-rejection behavior.
@Suite("Evolution search continuation")
struct EvolutionSearchContinuationTests {
    @MainActor
    @Test func continuationExploresWithinRejectedGenerationBudget() async throws {
        let directory = try continuationTemporaryDirectory()
        defer { continuationCleanup(directory) }
        let backend = ContinuationRunBackend()
        let orchestrator = EvolutionRunOrchestrator(
            backend: backend,
            evaluator: ContinuationEvaluator(passingGenerations: [])
        )

        let result = await orchestrator.run(
            config: continuationRunConfig(
                runID: "continuation-budget",
                generationCount: 10,
                maxConsecutiveRejectedGenerations: 3
            ),
            gatePolicy: continuationGatePolicy(),
            artifactDirectory: directory
        )

        #expect(result.manifest.terminalState == .rejected)
        #expect(result.generations.count == 4)
        #expect(result.generations.allSatisfy { !$0.accepted })
        #expect(
            result.manifest.failureReason?.contains("search-gate-rejected:generation=3") == true
        )
        #expect(backend.generationRequests.count == 3)
        #expect(backend.generationRequests.allSatisfy { $0.eliteCandidateIDs.isEmpty })
        #expect(backend.generationRequests.allSatisfy { !$0.parentCandidateIDs.isEmpty })

        let artifacts = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
        #expect(artifacts.manifest.terminalState == .rejected)
        #expect(artifacts.generations.count == 4)
    }

    @MainActor
    @Test func defaultBudgetStopsAtFirstRejectedGeneration() async throws {
        let directory = try continuationTemporaryDirectory()
        defer { continuationCleanup(directory) }
        let backend = ContinuationRunBackend()
        let orchestrator = EvolutionRunOrchestrator(
            backend: backend,
            evaluator: ContinuationEvaluator(passingGenerations: [])
        )

        let result = await orchestrator.run(
            config: continuationRunConfig(
                runID: "continuation-default",
                generationCount: 10,
                maxConsecutiveRejectedGenerations: nil
            ),
            gatePolicy: continuationGatePolicy(),
            artifactDirectory: directory
        )

        #expect(result.manifest.terminalState == .rejected)
        #expect(result.generations.count == 1)
        #expect(backend.generationRequests.isEmpty)
    }

    @MainActor
    @Test func acceptedGenerationResetsRejectedBudget() async throws {
        let directory = try continuationTemporaryDirectory()
        defer { continuationCleanup(directory) }
        let backend = ContinuationRunBackend()
        let orchestrator = EvolutionRunOrchestrator(
            backend: backend,
            evaluator: ContinuationEvaluator(passingGenerations: [1])
        )

        let result = await orchestrator.run(
            config: continuationRunConfig(
                runID: "continuation-reset",
                generationCount: 10,
                maxConsecutiveRejectedGenerations: 1
            ),
            gatePolicy: continuationGatePolicy(),
            artifactDirectory: directory
        )

        // gen0 rejected (1 <= budget), gen1 accepted (reset), gen2 rejected
        // (1 <= budget), gen3 rejected (2 > budget) -> stop after 4 records.
        #expect(result.generations.count == 4)
        #expect(result.generations.map(\.accepted) == [false, true, false, false])
        #expect(
            result.manifest.failureReason?.contains("search-gate-rejected:generation=3") == true
        )
    }

    @Test func explorationRankingPrefersSafetyThenPassRateThenFitness() {
        let policy = EvolutionSearchContinuationPolicy()
        let fitness = [
            continuationSummary(id: "unsafe-high-fitness", pass: 0.5, safety: 1, fitness: 100),
            continuationSummary(id: "safe-low-pass", pass: 0.2, safety: 0, fitness: -50),
            continuationSummary(id: "safe-high-pass", pass: 0.8, safety: 0, fitness: -90),
        ]

        let ranked = policy.explorationParentIDs(fitness: fitness, limit: 2)

        #expect(ranked == ["safe-high-pass", "safe-low-pass"])
    }

    @Test func explorationRankingPrefersFullScenarioEvidence() {
        let policy = EvolutionSearchContinuationPolicy()
        let fitness = [
            continuationSummary(id: "screening-best", pass: 1, safety: 0, fitness: 999, full: false),
            continuationSummary(id: "full-worst", pass: 0, safety: 1, fitness: -999),
        ]

        let ranked = policy.explorationParentIDs(fitness: fitness, limit: 2)

        #expect(ranked == ["full-worst"])
    }
}

private func continuationSummary(
    id: String,
    pass: Double,
    safety: Double,
    fitness: Double,
    full: Bool = true
) -> FitnessSummary {
    FitnessSummary(
        runID: "continuation",
        generationIndex: 0,
        candidateID: id,
        taskID: "attitude",
        evaluationFidelity: full ? .fullScenario : .screening(maximumControlStepsPerEpisode: 100),
        scalarFitness: fitness,
        rewardAverage: fitness,
        taskPassRate: pass,
        safetyViolationRate: safety
    )
}

private func continuationRunConfig(
    runID: String,
    generationCount: Int,
    maxConsecutiveRejectedGenerations: Int?
) -> EvolutionRunConfig {
    EvolutionRunConfig(
        runID: runID,
        taskID: "attitude",
        configHash: "config-hash",
        policyID: "manasMojo",
        populationSize: 3,
        generationCount: generationCount,
        eliteCount: 1,
        workerCount: 1,
        mutationRate: 0.1,
        maxConsecutiveRejectedGenerations: maxConsecutiveRejectedGenerations
    )
}

private func continuationGatePolicy() -> EvolutionGatePolicy {
    EvolutionGatePolicy(
        eliteCount: 1,
        minimumTaskPassRate: 1,
        maximumSafetyViolationRate: 0
    )
}

private func continuationTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "kuyu-search-continuation-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func continuationCleanup(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove \(url.path): \(error)")
    }
}

@MainActor
private final class ContinuationEvaluator: EvolutionCandidateEvaluating {
    private let passingGenerations: Set<Int>

    init(passingGenerations: Set<Int>) {
        self.passingGenerations = passingGenerations
    }

    func evaluateCandidate(
        request: EvolutionCandidateEvaluationRequest
    ) async throws -> FitnessSummary {
        let generationIndex = request.candidate.generationIndex
        let rank = Double(Int(request.candidate.candidateID.split(separator: "c").last ?? "0") ?? 0)
        let passes = passingGenerations.contains(generationIndex)
        return FitnessSummary(
            runID: request.config.runID,
            generationIndex: generationIndex,
            candidateID: request.candidate.candidateID,
            taskID: request.config.taskID,
            scalarFitness: Double(generationIndex) * 10 + rank,
            rewardAverage: Double(generationIndex) * 10 + rank,
            taskPassRate: passes ? 1 : 0,
            safetyViolationRate: passes ? 0 : 1,
            holdTimeRatio: 1
        )
    }
}

private final class ContinuationRunBackend: EvolutionaryTrainingBackend {
    private let recordedGenerationRequests = Mutex<[EvolutionGenerationRequest]>([])

    var generationRequests: [EvolutionGenerationRequest] {
        recordedGenerationRequests.withLock { $0 }
    }

    func seedPopulation(request: EvolutionSeedRequest) async throws -> EvolutionPopulation {
        try population(
            config: request.config,
            generationIndex: 0,
            artifactDirectory: request.artifactDirectory
        )
    }

    func produceNextGeneration(
        request: EvolutionGenerationRequest
    ) async throws -> EvolutionPopulation {
        recordedGenerationRequests.withLock { $0.append(request) }
        return try population(
            config: request.config,
            generationIndex: request.previousPopulation.generationIndex + 1,
            artifactDirectory: request.generationArtifactDirectory
        )
    }

    private func population(
        config: EvolutionRunConfig,
        generationIndex: Int,
        artifactDirectory: URL
    ) throws -> EvolutionPopulation {
        let candidates = try (0..<config.populationSize).map { index in
            let isIncumbent = generationIndex == 0 && index == 0
            let checkpointID = "checkpoint-g\(generationIndex)-c\(index)"
            let checkpointURL = artifactDirectory
                .appendingPathComponent("checkpoints", isDirectory: true)
                .appendingPathComponent(checkpointID, isDirectory: true)
            try FileManager.default.createDirectory(
                at: checkpointURL,
                withIntermediateDirectories: true
            )
            try Data("checkpoint:\(checkpointID)".utf8).write(
                to: checkpointURL.appendingPathComponent("manifest.json"),
                options: [.atomic]
            )
            return GenomeCandidate(
                runID: config.runID,
                generationIndex: generationIndex,
                candidateID: "g\(generationIndex)-c\(index)",
                genomeID: "genome-g\(generationIndex)-c\(index)",
                checkpointID: checkpointID,
                checkpointURL: checkpointURL,
                mutationRate: isIncumbent ? 0 : config.mutationRate,
                mutationNoiseScale: isIncumbent ? 0 : config.mutationNoiseScale,
                isIncumbent: isIncumbent
            )
        }
        return EvolutionPopulation(
            runID: config.runID,
            generationIndex: generationIndex,
            candidates: candidates
        )
    }
}
