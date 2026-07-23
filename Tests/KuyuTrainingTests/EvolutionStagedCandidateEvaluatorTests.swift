import Foundation
import Synchronization
import Testing

@testable import KuyuTraining

@Suite("Evolution staged candidate evaluator")
struct EvolutionStagedCandidateEvaluatorTests {
    @Test func refinesRankedCandidatesAndRetainsIncumbent() async throws {
        let candidates = makeCandidates(count: 4, incumbentIndex: 3)
        let screening = StageFitnessEvaluator(values: [
            "c0": 4,
            "c1": 3,
            "c2": 2,
            "c3": 1,
        ])
        let refinement = StageFitnessEvaluator(values: [
            "c0": 10,
            "c3": 20,
        ])
        let policy = TrainingCandidateRefinementPolicy(
            candidateFraction: 0.25,
            minimumCandidateCount: 1,
            retainsIncumbent: true
        )
        let evaluator = EvolutionStagedCandidateEvaluator(
            screeningEvaluator: screening,
            refinementEvaluator: refinement,
            refinementPolicy: policy,
            refinementGatePolicy: permissiveGatePolicy()
        )
        let config = makeConfig(policy: policy, populationSize: candidates.count)

        let summaries = try await evaluator.evaluateCandidates(
            request: EvolutionCandidateBatchEvaluationRequest(
                config: config,
                candidates: candidates,
                generationArtifactDirectory: URL(fileURLWithPath: "/tmp/staged-evaluation"),
                workerCount: 1,
                populationSize: candidates.count
            )
        )

        #expect(summaries.map(\.candidateID) == ["c0", "c1", "c2", "c3"])
        #expect(summaries.first { $0.candidateID == "c0" }?.scalarFitness == 10)
        #expect(summaries.first { $0.candidateID == "c3" }?.scalarFitness == 20)
        #expect(summaries.first { $0.candidateID == "c0" }?.failureReasons.isEmpty == true)
        #expect(summaries.first { $0.candidateID == "c3" }?.failureReasons.isEmpty == true)
        #expect(
            summaries.first { $0.candidateID == "c1" }?.failureReasons
                .contains("search-refinement-not-selected") == true
        )
        #expect(
            summaries.first { $0.candidateID == "c2" }?.failureReasons
                .contains("search-refinement-not-selected") == true
        )
        #expect(await screening.observedPhases() == [.screening])
        #expect(await refinement.observedPhases() == [.refinement])
        #expect(await refinement.observedCandidateIDs() == [["c0", "c3"]])
    }

    @Test func rejectsEvaluatorPolicyThatDiffersFromRunContract() async throws {
        let configured = TrainingCandidateRefinementPolicy(candidateFraction: 0.5)
        let injected = TrainingCandidateRefinementPolicy(candidateFraction: 0.25)
        let evaluator = EvolutionStagedCandidateEvaluator(
            screeningEvaluator: StageFitnessEvaluator(values: ["c0": 1]),
            refinementEvaluator: StageFitnessEvaluator(values: ["c0": 1]),
            refinementPolicy: injected,
            refinementGatePolicy: permissiveGatePolicy()
        )

        await #expect(throws: EvolutionStagedCandidateEvaluator.EvaluationError.refinementPolicyMismatch) {
            _ = try await evaluator.evaluateCandidates(
                request: EvolutionCandidateBatchEvaluationRequest(
                    config: makeConfig(policy: configured, populationSize: 1),
                    candidates: makeCandidates(count: 1, incumbentIndex: 0),
                    generationArtifactDirectory: URL(fileURLWithPath: "/tmp/staged-evaluation"),
                    workerCount: 1
                )
            )
        }
    }

    @Test func refinesLaterGenerationCarryoverWithoutMarkingItAsIncumbent() async throws {
        let candidates = [
            GenomeCandidate(
                runID: "run",
                generationIndex: 2,
                candidateID: "carryover",
                genomeID: "carryover-genome",
                isCarryover: true
            ),
            GenomeCandidate(
                runID: "run",
                generationIndex: 2,
                candidateID: "ranked",
                genomeID: "ranked-genome"
            ),
        ]
        let screening = StageFitnessEvaluator(values: [
            "carryover": 1,
            "ranked": 2,
        ])
        let refinement = StageFitnessEvaluator(values: [
            "carryover": 10,
            "ranked": 20,
        ])
        let policy = TrainingCandidateRefinementPolicy(
            candidateFraction: 0.5,
            minimumCandidateCount: 1,
            retainsIncumbent: true
        )
        let evaluator = EvolutionStagedCandidateEvaluator(
            screeningEvaluator: screening,
            refinementEvaluator: refinement,
            refinementPolicy: policy,
            refinementGatePolicy: permissiveGatePolicy()
        )

        let summaries = try await evaluator.evaluateCandidates(
            request: EvolutionCandidateBatchEvaluationRequest(
                config: makeConfig(policy: policy, populationSize: candidates.count),
                candidates: candidates,
                generationArtifactDirectory: URL(fileURLWithPath: "/tmp/staged-carryover-evaluation"),
                workerCount: 1
            )
        )

        #expect(summaries.allSatisfy { $0.failureReasons.isEmpty })
        #expect(await refinement.observedCandidateIDs() == [["carryover", "ranked"]])
    }

    @Test func backfillsRefinementWhenScreeningLeadersFailFullScenarioGate() async throws {
        let candidates = makeCandidates(count: 4, incumbentIndex: 3)
        let screening = StageFitnessEvaluator(values: [
            "c0": 4,
            "c1": 3,
            "c2": 2,
            "c3": 1,
        ])
        let refinement = StageFitnessEvaluator(
            values: ["c0": 4, "c1": 3, "c2": 2, "c3": 1],
            unsafeInFullScenario: ["c0", "c1"]
        )
        let policy = TrainingCandidateRefinementPolicy(
            candidateFraction: 0.5,
            minimumCandidateCount: 2,
            retainsIncumbent: true
        )
        let evaluator = EvolutionStagedCandidateEvaluator(
            screeningEvaluator: screening,
            refinementEvaluator: refinement,
            refinementPolicy: policy,
            refinementGatePolicy: EvolutionGatePolicy(
                eliteCount: 2,
                minimumTaskPassRate: 1,
                maximumSafetyViolationRate: 0
            )
        )

        let summaries = try await evaluator.evaluateCandidates(
            request: EvolutionCandidateBatchEvaluationRequest(
                config: makeConfig(policy: policy, populationSize: candidates.count, eliteCount: 2),
                candidates: candidates,
                generationArtifactDirectory: URL(fileURLWithPath: "/tmp/staged-backfill-evaluation"),
                workerCount: 1
            )
        )

        #expect(await refinement.observedPhases() == [.refinement, .refinementBackfill])
        #expect(await refinement.observedCandidateIDs() == [["c0", "c1", "c3"], ["c2"]])
        #expect(summaries.first { $0.candidateID == "c2" }?.evaluationFidelity == .fullScenario)
        #expect(summaries.first { $0.candidateID == "c2" }?.failureReasons.isEmpty == true)
    }

    @Test func gateReportsBestEligibleRefinedCandidate() {
        let summaries = [
            FitnessSummary(
                runID: "run",
                generationIndex: 0,
                candidateID: "screening-only",
                taskID: "attitude",
                evaluationFidelity: .screening(maximumControlStepsPerEpisode: 100),
                scalarFitness: 100,
                rewardAverage: 100,
                taskPassRate: 0,
                safetyViolationRate: 0
            ),
            FitnessSummary(
                runID: "run",
                generationIndex: 0,
                candidateID: "refined",
                taskID: "attitude",
                scalarFitness: 10,
                rewardAverage: 10,
                taskPassRate: 0,
                safetyViolationRate: 0
            ),
        ]

        let report = EvolutionGatePolicy(
            eliteCount: 1,
            minimumTaskPassRate: 0,
            maximumSafetyViolationRate: 1
        ).report(
            runID: "run",
            generationIndex: 0,
            fitness: summaries
        )

        #expect(report.bestCandidateID == "refined")
        #expect(report.bestFitness == 10)
        #expect(report.eliteCandidateIDs == ["refined"])
    }

    private func makeCandidates(count: Int, incumbentIndex: Int) -> [GenomeCandidate] {
        (0..<count).map { index in
            GenomeCandidate(
                runID: "run",
                generationIndex: 0,
                candidateID: "c\(index)",
                genomeID: "g\(index)",
                isIncumbent: index == incumbentIndex
            )
        }
    }

    private func makeConfig(
        policy: TrainingCandidateRefinementPolicy,
        populationSize: Int,
        eliteCount: Int = 1
    ) -> EvolutionRunConfig {
        EvolutionRunConfig(
            runID: "run",
            taskID: "attitude",
            configHash: "config",
            policyID: "policy",
            populationSize: populationSize,
            generationCount: 1,
            eliteCount: eliteCount,
            candidateEvaluationConcurrency: 1,
            searchEvaluationFidelity: .screening(maximumControlStepsPerEpisode: 100),
            searchRefinementPolicy: policy,
            mutationRate: 0.1
        )
    }

    private func permissiveGatePolicy() -> EvolutionGatePolicy {
        EvolutionGatePolicy(
            eliteCount: 1,
            minimumTaskPassRate: 0,
            maximumSafetyViolationRate: 1
        )
    }
}

private actor StageFitnessEvaluator: EvolutionCandidateBatchEvaluating {
    private let values: [String: Double]
    private let unsafeInFullScenario: Set<String>
    private var phases: [TrainingWorkPhase] = []
    private var candidateIDs: [[String]] = []

    init(values: [String: Double], unsafeInFullScenario: Set<String> = []) {
        self.values = values
        self.unsafeInFullScenario = unsafeInFullScenario
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
        candidateIDs.append(request.candidates.map(\.candidateID))
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

    func observedPhases() -> [TrainingWorkPhase] {
        phases
    }

    func observedCandidateIDs() -> [[String]] {
        candidateIDs
    }

    private func summary(
        config: EvolutionRunConfig,
        candidate: GenomeCandidate,
        fidelity: TrainingEvaluationFidelity
    ) -> FitnessSummary {
        let value = values[candidate.candidateID] ?? -1
        return FitnessSummary(
            runID: config.runID,
            generationIndex: candidate.generationIndex,
            candidateID: candidate.candidateID,
            taskID: config.taskID,
            evaluationFidelity: fidelity,
            scalarFitness: value,
            rewardAverage: value,
            taskPassRate: fidelity.isFullScenario && unsafeInFullScenario.contains(candidate.candidateID) ? 0 : 1,
            safetyViolationRate: fidelity.isFullScenario && unsafeInFullScenario.contains(candidate.candidateID) ? 1 : 0
        )
    }
}
