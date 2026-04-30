import Foundation
import Testing
@testable import KuyuTraining

@MainActor
@Test func evolutionRunOrchestratorWritesAutonomousEvolutionArtifacts() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend()
    let evaluator = FakeEvolutionEvaluator()
    let orchestrator = EvolutionRunOrchestrator(backend: backend, evaluator: evaluator)

    let result = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-run",
            taskID: "lift",
            configHash: "config-hash",
            policyID: "manasMLX",
            populationSize: 4,
            generationCount: 2,
            eliteCount: 2,
            workerCount: 2,
            candidateEvaluationConcurrency: 2,
            searchStrategy: .qualityDiversity,
            bootstrapSource: .teacher,
            worldModelUsage: .evaluationAssist,
            antitheticSampling: true,
            commonRandomSeed: 42,
            mutationRate: 0.08,
            mutationNoiseScale: 0.04,
            adaptiveMutation: EvolutionAdaptiveMutationConfig(
                enabled: true,
                decayFactor: 0.5,
                minimumMutationRate: 0.01,
                maximumMutationRate: 0.5,
                minimumNoiseScale: 0.001,
                maximumNoiseScale: 0.1
            )
        ),
        gatePolicy: EvolutionGatePolicy(
            eliteCount: 2,
            minimumTaskPassRate: 1.0,
            maximumSafetyViolationRate: 0,
            minimumHoldTimeRatio: 1.0
        ),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .completed)
    #expect(result.generations.count == 2)
    #expect(result.candidates.count == 8)
    #expect(result.fitness.count == 8)
    #expect(result.eliteArchive.bestCandidateID == "g1-c3")
    #expect(result.qualityDiversityArchive.cells.isEmpty == false)
    #expect(result.manifest.searchStrategy == .qualityDiversity)
    #expect(result.manifest.bootstrapSource == .teacher)
    #expect(result.manifest.worldModelUsage == .evaluationAssist)
    #expect(result.manifest.antitheticSampling)
    #expect(result.manifest.commonRandomSeed == 42)
    #expect(backend.seedRequests.count == 1)
    #expect(backend.nextGenerationRequests.count == 1)
    #expect(backend.seedRequests.first?.mutationRate == 0.08)
    #expect(backend.seedRequests.first?.mutationNoiseScale == 0.04)
    #expect(backend.seedRequests.first?.commonRandomSeed == 42)
    #expect(backend.nextGenerationRequests.first?.mutationRate == 0.04)
    #expect(backend.nextGenerationRequests.first?.mutationNoiseScale == 0.02)
    #expect(backend.nextGenerationRequests.first?.eliteCandidateIDs == ["g0-c3", "g0-c2"])
    #expect(evaluator.requests.count == 8)

    let artifacts = try EvolutionRunArtifactValidator().loadAndValidate(from: directory)
    #expect(artifacts.manifest.runID == "evolution-run")
    #expect(artifacts.eliteArchive.bestCandidateID == "g1-c3")
    #expect(artifacts.acceptedCheckpoint.accepted)
    #expect(artifacts.acceptedCheckpoint.candidateID == "g1-c3")
    #expect(artifacts.acceptedCheckpoint.checkpointURL?.path == "/tmp/checkpoint-g1-c3")
    #expect(artifacts.acceptedCheckpoint.bestCandidateID == "g1-c3")
    #expect(artifacts.acceptedCheckpoint.bestVsIncumbentDelta == 13)
    #expect(artifacts.contract.requiredFiles.contains(EvolutionQualityDiversityArchive.fileName))
    #expect(artifacts.contract.requiredFiles.contains(EvolutionAcceptedCheckpointDecision.fileName))
    #expect(artifacts.qualityDiversityArchive.cells == result.qualityDiversityArchive.cells)
    #expect(artifacts.generations.first?.qualityDiversityCellCount ?? 0 > 0)
    #expect(artifacts.generations.first?.mutationRate == 0.08)
    #expect(artifacts.generations.first?.mutationNoiseScale == 0.04)
    #expect(artifacts.generations.last?.eliteCandidateIDs == ["g1-c3", "g1-c2"])
}

@MainActor
@Test func evolutionRunOrchestratorRejectsWhenNoCandidatePassesGate() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend()
    let evaluator = FakeEvolutionEvaluator(taskPassRate: 0.5)
    let orchestrator = EvolutionRunOrchestrator(backend: backend, evaluator: evaluator)

    let result = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-rejected",
            taskID: "lift",
            configHash: "config-hash",
            policyID: "manasMLX",
            populationSize: 3,
            generationCount: 1,
            eliteCount: 1,
            workerCount: 1,
            mutationRate: 0.08
        ),
        gatePolicy: EvolutionGatePolicy(
            eliteCount: 1,
            minimumTaskPassRate: 1.0,
            maximumSafetyViolationRate: 0,
            minimumHoldTimeRatio: 1.0
        ),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .rejected)
    #expect(result.generations.first?.accepted == false)
    #expect(result.generations.first?.rejectionReasons.contains("no-candidate-passed-gate") == true)
    #expect(result.generations.first?.rejectionReasons.contains { $0.hasPrefix("task-pass-rate-below-min:g0-c") } == true)
    #expect(result.eliteArchive.eliteCandidateIDs.isEmpty)

    let artifacts = try EvolutionRunArtifactValidator().loadAndValidate(from: directory)
    #expect(artifacts.manifest.terminalState == .rejected)
    #expect(!artifacts.acceptedCheckpoint.accepted)
    #expect(artifacts.acceptedCheckpoint.candidateID == nil)
}

@MainActor
@Test func evolutionRunOrchestratorArchivesButDoesNotPublishWhenNoCandidateImprovesOnIncumbent() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend()
    let evaluator = FakeEvolutionEvaluator(fixedFitness: 1.0)
    let orchestrator = EvolutionRunOrchestrator(backend: backend, evaluator: evaluator)

    let result = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-no-incumbent-improvement",
            taskID: "lift",
            configHash: "config-hash",
            policyID: "manasMLX",
            populationSize: 3,
            generationCount: 1,
            eliteCount: 1,
            workerCount: 1,
            mutationRate: 0.08
        ),
        gatePolicy: EvolutionGatePolicy(
            eliteCount: 1,
            minimumTaskPassRate: 1.0,
            maximumSafetyViolationRate: 0,
            minimumHoldTimeRatio: 1.0,
            minimumImprovementOverIncumbent: 0
        ),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .completed)
    #expect(result.generations.first?.accepted == true)
    #expect(result.generations.first?.rejectionReasons.isEmpty == true)

    let artifacts = try EvolutionRunArtifactValidator().loadAndValidate(from: directory)
    #expect(artifacts.generations.first?.accepted == true)
    #expect(artifacts.acceptedCheckpoint.accepted == false)
    #expect(artifacts.acceptedCheckpoint.candidateID == nil)
    #expect(artifacts.acceptedCheckpoint.bestCandidateID == "g0-c0")
    #expect(artifacts.acceptedCheckpoint.reasons.contains { $0.hasPrefix("incumbent-improvement-below-min:") } == true)
}

@MainActor
@Test func evolutionRunOrchestratorKeepsEarlierAcceptedEliteWhenLaterGenerationRegresses() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend()
    let evaluator = FakeEvolutionEvaluator(generationTaskPassRates: [0: 1.0, 1: 0.0])
    let orchestrator = EvolutionRunOrchestrator(backend: backend, evaluator: evaluator)

    let result = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-regressed-after-acceptance",
            taskID: "lift",
            configHash: "config-hash",
            policyID: "manasMLX",
            populationSize: 3,
            generationCount: 2,
            eliteCount: 1,
            workerCount: 1,
            mutationRate: 0.08
        ),
        gatePolicy: EvolutionGatePolicy(
            eliteCount: 1,
            minimumTaskPassRate: 1.0,
            maximumSafetyViolationRate: 0,
            minimumHoldTimeRatio: 1.0
        ),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .completed)
    #expect(result.generations.map(\.accepted) == [true, false])
    #expect(result.eliteArchive.eliteCandidateIDs == ["g0-c2"])
    #expect(result.eliteArchive.bestCandidateID == "g0-c2")

    let artifacts = try EvolutionRunArtifactValidator().loadAndValidate(from: directory)
    #expect(artifacts.manifest.terminalState == .completed)
    #expect(artifacts.eliteArchive.bestCandidateID == "g0-c2")
}

@MainActor
@Test func evolutionArtifactValidatorRejectsNonFiniteFitness() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend()
    let evaluator = FakeEvolutionEvaluator(nonFiniteCandidateID: "g0-c1")
    let orchestrator = EvolutionRunOrchestrator(backend: backend, evaluator: evaluator)

    _ = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-nonfinite",
            taskID: "lift",
            configHash: "config-hash",
            policyID: "manasMLX",
            populationSize: 2,
            generationCount: 1,
            eliteCount: 1,
            workerCount: 1,
            mutationRate: 0.08
        ),
        artifactDirectory: directory
    )

    do {
        _ = try EvolutionRunArtifactValidator().loadAndValidate(from: directory)
        Issue.record("Expected evolution artifact validator to reject non-finite fitness")
    } catch let error as EvolutionRunArtifactValidator.ValidationError {
        #expect(error == .nonFiniteFitness(candidateID: "g0-c1"))
    }
}

@MainActor
@Test func evolutionArtifactValidatorRejectsTamperedQualityDiversityArchive() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend()
    let evaluator = FakeEvolutionEvaluator()
    let orchestrator = EvolutionRunOrchestrator(backend: backend, evaluator: evaluator)

    _ = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-tampered-qd",
            taskID: "lift",
            configHash: "config-hash",
            policyID: "manasMLX",
            populationSize: 2,
            generationCount: 1,
            eliteCount: 1,
            workerCount: 1,
            mutationRate: 0.08
        ),
        artifactDirectory: directory
    )

    let archive = EvolutionQualityDiversityArchive(
        runID: "evolution-tampered-qd",
        descriptorKeys: ["taskPassRate"],
        cells: [
            EvolutionQualityDiversityCell(
                cellID: "taskPassRate=10",
                candidateID: "missing-candidate",
                generationIndex: 0,
                fitness: 1,
                behaviorDescriptor: ["taskPassRate": 1]
            ),
        ]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(archive).write(
        to: directory.appendingPathComponent(EvolutionQualityDiversityArchive.fileName),
        options: [.atomic]
    )

    do {
        _ = try EvolutionRunArtifactValidator().loadAndValidate(from: directory)
        Issue.record("Expected evolution artifact validator to reject tampered quality diversity archive")
    } catch let error as EvolutionRunArtifactValidator.ValidationError {
        #expect(error == .qualityDiversityCandidateMissing("missing-candidate"))
    }
}

@MainActor
private final class FakeEvolutionBackend: EvolutionaryTrainingBackend {
    private(set) var seedRequests: [EvolutionSeedRequest] = []
    private(set) var nextGenerationRequests: [EvolutionGenerationRequest] = []

    func seedPopulation(request: EvolutionSeedRequest) async throws -> EvolutionPopulation {
        seedRequests.append(request)
        return population(
            config: request.config,
            generationIndex: 0,
            parents: [],
            mutationRate: request.mutationRate,
            mutationNoiseScale: request.mutationNoiseScale,
            commonRandomSeed: request.commonRandomSeed
        )
    }

    func produceNextGeneration(request: EvolutionGenerationRequest) async throws -> EvolutionPopulation {
        nextGenerationRequests.append(request)
        return population(
            config: request.config,
            generationIndex: request.previousPopulation.generationIndex + 1,
            parents: request.eliteCandidateIDs,
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
                    antitheticPairID: config.antitheticSampling ? "g\(generationIndex)-p\(index / 2)" : nil,
                    antitheticSign: config.antitheticSampling ? (index.isMultiple(of: 2) ? 1 : -1) : nil,
                    mutationSummary: isIncumbent ? "incumbent-parent" : (generationIndex == 0 ? "seeded" : "mutated"),
                    isIncumbent: isIncumbent
                )
            }
        )
    }
}

@MainActor
private final class FakeEvolutionEvaluator: EvolutionCandidateEvaluating {
    private(set) var requests: [EvolutionCandidateEvaluationRequest] = []
    let taskPassRate: Double
    let generationTaskPassRates: [Int: Double]
    let nonFiniteCandidateID: String?
    let fixedFitness: Double?

    init(
        taskPassRate: Double = 1.0,
        generationTaskPassRates: [Int: Double] = [:],
        nonFiniteCandidateID: String? = nil,
        fixedFitness: Double? = nil
    ) {
        self.taskPassRate = taskPassRate
        self.generationTaskPassRates = generationTaskPassRates
        self.nonFiniteCandidateID = nonFiniteCandidateID
        self.fixedFitness = fixedFitness
    }

    func evaluateCandidate(request: EvolutionCandidateEvaluationRequest) async throws -> FitnessSummary {
        requests.append(request)
        let candidateRank = Double(Int(request.candidate.candidateID.split(separator: "c").last ?? "0") ?? 0)
        let generationOffset = Double(request.candidate.generationIndex) * 10
        let finiteFitness = fixedFitness ?? (generationOffset + candidateRank)
        let scalarFitness = request.candidate.candidateID == nonFiniteCandidateID ? Double.nan : candidateRank
        return FitnessSummary(
            runID: request.config.runID,
            generationIndex: request.candidate.generationIndex,
            candidateID: request.candidate.candidateID,
            taskID: request.config.taskID,
            scalarFitness: request.candidate.candidateID == nonFiniteCandidateID ? scalarFitness : finiteFitness,
            rewardAverage: finiteFitness,
            taskPassRate: generationTaskPassRates[request.candidate.generationIndex] ?? taskPassRate,
            safetyViolationRate: 0,
            holdTimeRatio: 1.0,
            energyPenalty: 0.1,
            noveltyScore: candidateRank / 10,
            teacherDelta: nil,
            workerThroughput: Double(request.workerCount),
            behaviorDescriptor: [
                "candidateRank": candidateRank,
                "generationOffset": generationOffset,
            ]
        )
    }
}

private func evolutionTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-evolution-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func evolutionCleanup(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove \(url.path): \(error)")
    }
}
