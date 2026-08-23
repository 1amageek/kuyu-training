import Foundation
import Testing

@testable import KuyuTraining

// End-to-end behavioral coverage for refinement evidence fidelity: the run path
// from orchestrator through staged evaluation, gate, and terminal artifact
// validation. Contract-shape tests alone cannot catch a configuration that
// validates but can never complete; these tests execute the actual path.
@Suite("Evolution refinement fidelity run")
struct EvolutionRefinementFidelityRunTests {
    @MainActor
    @Test func boundedRefinementConfigFailsFastWithoutEvaluatingCandidates() async throws {
        let directory = try refinementRunTemporaryDirectory()
        defer { refinementRunCleanup(directory) }
        let screening = RefinementRunStageEvaluator()
        let refinement = RefinementRunStageEvaluator()
        let boundedPolicy = TrainingCandidateRefinementPolicy(
            evaluationFidelity: .screening(maximumControlStepsPerEpisode: 5_000)
        )
        let orchestrator = EvolutionRunOrchestrator(
            backend: RefinementRunBackend(),
            evaluator: EvolutionStagedCandidateEvaluator(
                screeningEvaluator: screening,
                refinementEvaluator: refinement,
                refinementPolicy: boundedPolicy,
                refinementGatePolicy: refinementRunGatePolicy()
            )
        )

        let result = await orchestrator.run(
            config: refinementRunConfig(
                runID: "refinement-fidelity-bounded",
                refinementPolicy: boundedPolicy
            ),
            gatePolicy: refinementRunGatePolicy(),
            artifactDirectory: directory
        )

        #expect(result.manifest.terminalState == .failed)
        #expect(result.manifest.failureReason?.contains("invalid-evolution-config") == true)
        #expect(
            result.manifest.failureReason?.contains("unsupportedBoundedRefinementFidelity") == true
        )
        #expect(result.fitness.isEmpty)
        #expect(await screening.observedPhases().isEmpty)
        #expect(await refinement.observedPhases().isEmpty)
    }

    @MainActor
    @Test func fullScenarioRefinementCompletesAndValidatesTerminalArtifacts() async throws {
        let directory = try refinementRunTemporaryDirectory()
        defer { refinementRunCleanup(directory) }
        let screening = RefinementRunStageEvaluator()
        let refinement = RefinementRunStageEvaluator()
        let policy = TrainingCandidateRefinementPolicy(
            evaluationFidelity: .fullScenario,
            candidateFraction: 0.5
        )
        let orchestrator = EvolutionRunOrchestrator(
            backend: RefinementRunBackend(),
            evaluator: EvolutionStagedCandidateEvaluator(
                screeningEvaluator: screening,
                refinementEvaluator: refinement,
                refinementPolicy: policy,
                refinementGatePolicy: refinementRunGatePolicy()
            )
        )

        let result = await orchestrator.run(
            config: refinementRunConfig(
                runID: "refinement-fidelity-full",
                refinementPolicy: policy
            ),
            gatePolicy: refinementRunGatePolicy(),
            artifactDirectory: directory
        )

        #expect(result.manifest.terminalState == .completed)
        #expect(result.generations.count == 2)
        #expect(result.generations.allSatisfy { $0.accepted })
        #expect(await screening.observedPhases() == [.screening, .screening])
        #expect(await refinement.observedPhases() == [.refinement, .refinement])

        // Generation 0 refines the top-2 screening leaders plus the retained
        // incumbent (3 candidates); generation 1 has no incumbent and refines 2.
        let refined = result.fitness.filter { $0.evaluationFidelity.isFullScenario }
        let screeningOnly = result.fitness.filter { !$0.evaluationFidelity.isFullScenario }
        #expect(refined.count == 5)
        #expect(screeningOnly.count == 1)
        #expect(screeningOnly.allSatisfy {
            $0.failureReasons.contains("search-refinement-not-selected")
        })

        let artifacts = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
        #expect(artifacts.manifest.terminalState == .completed)
        let bestCandidateID = try #require(artifacts.eliteArchive.bestCandidateID)
        let bestSummary = try #require(
            artifacts.fitness.first { $0.candidateID == bestCandidateID }
        )
        #expect(bestSummary.evaluationFidelity.isFullScenario)
    }
}

private func refinementRunConfig(
    runID: String,
    refinementPolicy: TrainingCandidateRefinementPolicy
) -> EvolutionRunConfig {
    EvolutionRunConfig(
        runID: runID,
        taskID: "attitude",
        configHash: "config-hash",
        policyID: "manasMojo",
        populationSize: 3,
        generationCount: 2,
        eliteCount: 1,
        workerCount: 1,
        candidateEvaluationConcurrency: 1,
        searchEvaluationFidelity: .screening(maximumControlStepsPerEpisode: 1_000),
        searchRefinementPolicy: refinementPolicy,
        mutationRate: 0.1
    )
}

private func refinementRunGatePolicy() -> EvolutionGatePolicy {
    EvolutionGatePolicy(
        eliteCount: 1,
        minimumTaskPassRate: 1,
        maximumSafetyViolationRate: 0
    )
}

private func refinementRunTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "kuyu-refinement-fidelity-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func refinementRunCleanup(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove \(url.path): \(error)")
    }
}

private actor RefinementRunStageEvaluator: EvolutionCandidateBatchEvaluating {
    private var phases: [TrainingWorkPhase] = []

    func observedPhases() -> [TrainingWorkPhase] {
        phases
    }

    func evaluateCandidate(
        request: EvolutionCandidateEvaluationRequest
    ) async throws -> FitnessSummary {
        summary(
            config: request.config,
            candidate: request.candidate,
            fidelity: request.config.searchEvaluationFidelity
        )
    }

    func evaluateCandidates(
        request: EvolutionCandidateBatchEvaluationRequest
    ) async throws -> [FitnessSummary] {
        phases.append(request.workPhase)
        let fidelity = request.workPhase == .screening
            ? request.config.searchEvaluationFidelity
            : request.config.searchRefinementPolicy?.evaluationFidelity ?? .fullScenario
        return request.candidates.map {
            summary(config: request.config, candidate: $0, fidelity: fidelity)
        }
    }

    func evaluateCandidates(
        request: EvolutionCandidateBatchEvaluationRequest,
        progressReporter: (any TrainingProgressReporting)?
    ) async throws -> [FitnessSummary] {
        _ = progressReporter
        return try await evaluateCandidates(request: request)
    }

    private func summary(
        config: EvolutionRunConfig,
        candidate: GenomeCandidate,
        fidelity: TrainingEvaluationFidelity
    ) -> FitnessSummary {
        let rank = Double(Int(candidate.candidateID.split(separator: "c").last ?? "0") ?? 0)
        let fitness = Double(candidate.generationIndex) * 10 + rank
        return FitnessSummary(
            runID: config.runID,
            generationIndex: candidate.generationIndex,
            candidateID: candidate.candidateID,
            taskID: config.taskID,
            evaluationFidelity: fidelity,
            scalarFitness: fitness,
            rewardAverage: fitness,
            taskPassRate: 1,
            safetyViolationRate: 0,
            holdTimeRatio: 1
        )
    }
}

private final class RefinementRunBackend: EvolutionaryTrainingBackend {
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
        try population(
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
