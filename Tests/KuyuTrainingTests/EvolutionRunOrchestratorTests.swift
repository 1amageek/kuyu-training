import Foundation
import Synchronization
import Testing
@testable import KuyuTraining

@MainActor
@Test func evolutionRunOrchestratorStopsEarlyWhenFitnessAndTaskQualityPlateau() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend()
    let evaluator = FakeEvolutionEvaluator(taskPassRate: 0, fixedFitness: 1)
    let orchestrator = EvolutionRunOrchestrator(backend: backend, evaluator: evaluator)

    let result = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-early-stop-plateau",
            taskID: "lift",
            configHash: "config-hash",
            policyID: "manasMLX",
            populationSize: 3,
            generationCount: 8,
            eliteCount: 1,
            workerCount: 1,
            mutationRate: 0.08,
            earlyStopping: EvolutionEarlyStoppingConfig(
                enabled: true,
                patienceGenerations: 2,
                minimumFitnessImprovement: 0.001,
                minimumTaskPassRateImprovement: 0.001,
                minimumHoldTimeRatioImprovement: 0.001
            )
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
    #expect(result.manifest.generationCount == 8)
    #expect(result.generations.count == 3)
    #expect(result.fitness.count == 9)
    #expect(result.manifest.failureReason?.hasPrefix("early-stopped:plateau") == true)
    #expect(backend.nextGenerationRequests.count == 2)

    let artifacts = try EvolutionRunArtifactValidator().loadAndValidate(from: directory)
    #expect(artifacts.manifest.failureReason?.hasPrefix("early-stopped:plateau") == true)
    #expect(artifacts.generations.count == 3)
    #expect(artifacts.fitness.count == 9)
}

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
    #expect(result.evaluationTraces.count == 8)
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
    #expect(backend.nextGenerationRequests.first?.parentCandidateIDs == ["g0-c3", "g0-c2", "g0-c1", "g0-c0"])
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
    #expect(artifacts.contract.requiredFiles.contains("evaluation-trace.jsonl"))
    #expect(artifacts.evaluationTraces.count == 8)
    #expect(artifacts.evaluationTraces.allSatisfy { $0.durationSeconds.isFinite && $0.durationSeconds >= 0 })
    #expect(artifacts.qualityDiversityArchive.cells == result.qualityDiversityArchive.cells)
    #expect(artifacts.generations.first?.qualityDiversityCellCount ?? 0 > 0)
    #expect(artifacts.generations.first?.mutationRate == 0.08)
    #expect(artifacts.generations.first?.mutationNoiseScale == 0.04)
    #expect(artifacts.generations.last?.eliteCandidateIDs == ["g1-c3", "g1-c2"])
}

@MainActor
@Test func evolutionRunOrchestratorEvaluatesCandidatesConcurrently() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend()
    let probe = EvaluationConcurrencyProbe()
    let evaluator = SlowEvolutionEvaluator(probe: probe)
    let orchestrator = EvolutionRunOrchestrator(backend: backend, evaluator: evaluator)

    let result = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-concurrent-evaluation",
            taskID: "lift",
            configHash: "config-hash",
            policyID: "manasMLX",
            populationSize: 4,
            generationCount: 1,
            eliteCount: 1,
            workerCount: 1,
            candidateEvaluationConcurrency: 4,
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
    #expect(await probe.maximumActiveCount() > 1)
    #expect(result.evaluationTraces.contains { $0.activeEvaluationCountAtStart > 1 })
}

@MainActor
@Test func evolutionRunOrchestratorUsesBatchEvaluatorWhenAvailable() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend()
    let evaluator = FakeBatchEvolutionEvaluator()
    let orchestrator = EvolutionRunOrchestrator(backend: backend, evaluator: evaluator)

    let result = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-batch-evaluation",
            taskID: "lift",
            configHash: "config-hash",
            policyID: "manasMLX",
            populationSize: 7,
            generationCount: 1,
            eliteCount: 1,
            workerCount: 2,
            candidateEvaluationConcurrency: 3,
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
    #expect(result.fitness.map(\.candidateID) == [
        "g0-c0",
        "g0-c1",
        "g0-c2",
        "g0-c3",
        "g0-c4",
        "g0-c5",
        "g0-c6"
    ])
    #expect(evaluator.singleCandidateRequestCount == 0)
    #expect(evaluator.batchCandidateIDs == [
        ["g0-c0", "g0-c1", "g0-c2"],
        ["g0-c3", "g0-c4", "g0-c5"],
        ["g0-c6"]
    ])
    #expect(result.evaluationTraces.allSatisfy { $0.requestedConcurrency == 3 })
}

@MainActor
@Test func evolutionRunOrchestratorStreamsCandidateEventsBeforeGenerationCompletion() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend()
    let evaluator = SlowEvolutionEvaluator(probe: EvaluationConcurrencyProbe())
    let orchestrator = EvolutionRunOrchestrator(backend: backend, evaluator: evaluator)
    let events = Mutex<[String]>([])

    let result = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-streaming-events",
            taskID: "lift",
            configHash: "config-hash",
            policyID: "manasMLX",
            populationSize: 4,
            generationCount: 1,
            eliteCount: 1,
            workerCount: 2,
            candidateEvaluationConcurrency: 4,
            mutationRate: 0.08
        ),
        gatePolicy: EvolutionGatePolicy(
            eliteCount: 1,
            minimumTaskPassRate: 1.0,
            maximumSafetyViolationRate: 0,
            minimumHoldTimeRatio: 1.0
        ),
        artifactDirectory: directory,
        onEvent: { event in
            switch event {
            case let .generationStarted(index):
                events.withLock { $0.append("generation-started:\(index)") }
            case let .candidateEvaluated(summary):
                events.withLock { $0.append("candidate:\(summary.candidateID)") }
            case let .generationCompleted(record):
                events.withLock { $0.append("generation-completed:\(record.generationIndex)") }
            default:
                break
            }
        }
    )

    #expect(result.manifest.terminalState == .completed)
    let recordedEvents = events.withLock { $0 }
    let candidateEventCount = recordedEvents.filter { $0.hasPrefix("candidate:") }.count
    #expect(candidateEventCount == 4)

    guard let firstCandidateIndex = recordedEvents.firstIndex(where: { $0.hasPrefix("candidate:") }) else {
        Issue.record("Expected at least one candidate event")
        return
    }
    guard let generationCompletedIndex = recordedEvents.firstIndex(of: "generation-completed:0") else {
        Issue.record("Expected generation completed event")
        return
    }
    #expect(firstCandidateIndex < generationCompletedIndex)
}

@MainActor
@Test func evolutionRunOrchestratorWritesValidArtifactsWhenBatchEvaluationIsCancelledMidRun() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend()
    let evaluator = CancellingBatchEvolutionEvaluator(cancelAtGeneration: 1)
    let orchestrator = EvolutionRunOrchestrator(backend: backend, evaluator: evaluator)

    let result = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-cancelled-mid-batch",
            taskID: "lift",
            configHash: "config-hash",
            policyID: "manasMLX",
            populationSize: 3,
            generationCount: 4,
            eliteCount: 1,
            workerCount: 1,
            candidateEvaluationConcurrency: 3,
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

    #expect(result.manifest.terminalState == .cancelled)
    #expect(result.generations.count == 1)
    #expect(result.candidates.count == 6)
    #expect(result.fitness.count == 6)
    #expect(result.evaluationTraces.count == 6)
    #expect(result.eliteArchive.bestCandidateID == "g0-c2")
    #expect(result.fitness.filter { $0.generationIndex == 1 }.allSatisfy {
        $0.failureReasons == ["evaluation-cancelled"]
            && $0.behaviorDescriptor["evaluation.cancelled"] == 1
    })

    let artifacts = try EvolutionRunArtifactValidator().loadAndValidate(from: directory)
    #expect(artifacts.manifest.terminalState == .cancelled)
    #expect(artifacts.candidates.count == 6)
    #expect(artifacts.fitness.count == 6)
    #expect(artifacts.evaluationTraces.count == 6)
    #expect(artifacts.eliteArchive.bestCandidateID == "g0-c2")
    #expect(artifacts.acceptedCheckpoint.accepted == false)
    #expect(artifacts.acceptedCheckpoint.bestCandidateID == "g0-c2")
}

@MainActor
@Test func evolutionRunOrchestratorDoesNotDecayMutationWhenAcceptedGenerationDoesNotBeatIncumbent() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend()
    let evaluator = FakeEvolutionEvaluator(fixedFitness: 1)
    let orchestrator = EvolutionRunOrchestrator(backend: backend, evaluator: evaluator)

    let result = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-adaptive-no-incumbent-improvement",
            taskID: "lift",
            configHash: "config-hash",
            policyID: "manasMLX",
            populationSize: 3,
            generationCount: 2,
            eliteCount: 1,
            workerCount: 1,
            mutationRate: 0.04,
            mutationNoiseScale: 0.002,
            adaptiveMutation: EvolutionAdaptiveMutationConfig(
                enabled: true,
                increaseFactor: 1.5,
                decayFactor: 0.5,
                minimumMutationRate: 0.01,
                maximumMutationRate: 0.2,
                minimumNoiseScale: 0.0005,
                maximumNoiseScale: 0.01
            )
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

    #expect(result.generations.first?.accepted == true)
    #expect(result.generations.first?.bestVsIncumbentDelta == 0)
    #expect(result.generations.first?.incumbentImproved == false)
    #expect(backend.nextGenerationRequests.first?.mutationRate == 0.06)
    #expect(backend.nextGenerationRequests.first?.mutationNoiseScale == 0.003)
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
@Test func evolutionRunOrchestratorRejectsLowNoveltyCandidatesWhenRequired() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend()
    let evaluator = FakeEvolutionEvaluator()
    let orchestrator = EvolutionRunOrchestrator(backend: backend, evaluator: evaluator)

    let result = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-low-novelty",
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
            minimumNoveltyScore: 0.25
        ),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .rejected)
    #expect(result.generations.first?.rejectionReasons.contains("no-candidate-passed-gate") == true)
    #expect(result.generations.first?.rejectionReasons.contains { $0.hasPrefix("novelty-below-min:g0-c2:") } == true)
}

@MainActor
@Test func evolutionRunOrchestratorComputesNoveltyForDuplicateBehavior() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend()
    let evaluator = DuplicateBehaviorEvolutionEvaluator()
    let orchestrator = EvolutionRunOrchestrator(backend: backend, evaluator: evaluator)

    let result = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-duplicate-behavior",
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
            minimumNoveltyScore: 0.1
        ),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .rejected)
    #expect(result.fitness.allSatisfy { $0.noveltyScore == 0 })
    #expect(result.fitness.allSatisfy { $0.altitudeErrorRatio == 0.75 })
    #expect(result.generations.first?.rejectionReasons.contains { $0.hasPrefix("novelty-below-min:g0-c") } == true)
}

@MainActor
@Test func evolutionRunOrchestratorDoesNotPublishScalarImprovementWithTaskRegression() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend()
    let evaluator = PublishRegressionEvolutionEvaluator()
    let orchestrator = EvolutionRunOrchestrator(backend: backend, evaluator: evaluator)

    let result = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-publish-regression",
            taskID: "lift",
            configHash: "config-hash",
            policyID: "manasMLX",
            populationSize: 2,
            generationCount: 1,
            eliteCount: 1,
            workerCount: 1,
            mutationRate: 0.08
        ),
        gatePolicy: EvolutionGatePolicy(
            eliteCount: 1,
            minimumTaskPassRate: 0.5,
            maximumSafetyViolationRate: 0,
            minimumHoldTimeRatio: 0.5,
            minimumImprovementOverIncumbent: 0
        ),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .completed)
    #expect(result.eliteArchive.bestCandidateID == "g0-c1")

    let artifacts = try EvolutionRunArtifactValidator().loadAndValidate(from: directory)
    #expect(artifacts.acceptedCheckpoint.accepted == false)
    #expect(artifacts.acceptedCheckpoint.candidateID == nil)
    #expect(artifacts.acceptedCheckpoint.bestCandidateID == "g0-c1")
    #expect(artifacts.acceptedCheckpoint.publishMetricRegressions.contains {
        $0.hasPrefix("publish-metric-regression:taskPassRate:")
    })
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
    #expect(result.generations.first?.incumbentImproved == false)
    #expect(result.generations.first?.rejectionReasons.isEmpty == true)

    let artifacts = try EvolutionRunArtifactValidator().loadAndValidate(from: directory)
    #expect(artifacts.generations.first?.accepted == true)
    #expect(artifacts.generations.first?.incumbentImproved == false)
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
@Test func typedTrainingBackendAdapterBridgesLegacyEvolutionBackend() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let config = EvolutionRunConfig(
        runID: "typed-adapter",
        taskID: "lift",
        configHash: "config-hash",
        policyID: "manasMLX",
        populationSize: 3,
        generationCount: 1,
        eliteCount: 1,
        workerCount: 1,
        mutationRate: 0.08,
        mutationNoiseScale: 0.04
    )
    let backend = FakeEvolutionBackend()
    let evaluator = FakeEvolutionEvaluator()
    // Drive the generic TypedTrainingBackend contract end-to-end through the real
    // legacy→typed adapter, proving the typed layer is functional and connected to the
    // production backend protocols (not orphan scaffolding).
    let typed = EvolutionTypedBackendAdapter(config: config, backend: backend, evaluator: evaluator)

    let source = ModelBundleReference(bundleID: "source", kind: .source, url: URL(fileURLWithPath: "/tmp/source.manasbundle"))
    let checkpoint = try await typed.loadCheckpoint(source)
    #expect(checkpoint == source)

    let candidates = try await typed.seedPopulation(
        from: checkpoint,
        request: PopulationSeedRequest(runID: config.runID, populationSize: 3, seed: 42, artifactRoot: directory)
    )
    #expect(candidates.count == 3)
    #expect(backend.seedRequests.count == 1)

    let firstCandidate = try #require(candidates.first)
    let context = TrainingEvaluationContext<TrainingNoObservation, TrainingNoAction>(
        runID: config.runID,
        taskProfileID: "lift",
        artifactRoot: directory,
        seed: 42,
        workerCount: 1
    )
    let evaluation = try await typed.evaluate(firstCandidate, in: context)
    #expect(evaluation.candidateID == firstCandidate.candidateID)
    #expect(evaluation.fitness.isFinite)
    #expect(evaluator.requests.count == 1)

    let offspring = try await typed.reproduce(ReproductionRequest(
        runID: config.runID,
        generation: 1,
        parents: [firstCandidate],
        targetPopulationSize: 3,
        mutationRate: 0.04,
        mutationNoiseScale: 0.02,
        seed: 7,
        artifactRoot: directory
    ))
    #expect(offspring.count == 3)
    #expect(backend.nextGenerationRequests.count == 1)

    let destination = ModelBundleReference(bundleID: "accepted", kind: .accepted, url: URL(fileURLWithPath: "/tmp/accepted.manasbundle"))
    let published = try await typed.publish(firstCandidate, request: CheckpointPublicationRequest(
        runID: config.runID,
        candidateID: firstCandidate.candidateID,
        destination: destination,
        artifactRoot: directory
    ))
    #expect(published.kind == .accepted)
    #expect(published.url == firstCandidate.checkpointURL)
}

private actor EvaluationConcurrencyProbe {
    private var activeCount = 0
    private var maximumActive = 0

    func enter() {
        activeCount += 1
        maximumActive = max(maximumActive, activeCount)
    }

    func leave() {
        activeCount -= 1
    }

    func maximumActiveCount() -> Int {
        maximumActive
    }
}

@MainActor
private final class CancellingBatchEvolutionEvaluator: EvolutionCandidateBatchEvaluating {
    let cancelAtGeneration: Int

    init(cancelAtGeneration: Int) {
        self.cancelAtGeneration = cancelAtGeneration
    }

    func evaluateCandidate(request: EvolutionCandidateEvaluationRequest) async throws -> FitnessSummary {
        summary(config: request.config, candidate: request.candidate, workerCount: request.workerCount)
    }

    func evaluateCandidates(request: EvolutionCandidateBatchEvaluationRequest) async throws -> [FitnessSummary] {
        if request.candidates.contains(where: { $0.generationIndex == cancelAtGeneration }) {
            throw CancellationError()
        }
        return request.candidates.map { candidate in
            summary(config: request.config, candidate: candidate, workerCount: request.workerCount)
        }
    }

    private func summary(
        config: EvolutionRunConfig,
        candidate: GenomeCandidate,
        workerCount: Int
    ) -> FitnessSummary {
        let candidateRank = Double(Int(candidate.candidateID.split(separator: "c").last ?? "0") ?? 0)
        let generationOffset = Double(candidate.generationIndex) * 10
        let fitness = generationOffset + candidateRank
        return FitnessSummary(
            runID: config.runID,
            generationIndex: candidate.generationIndex,
            candidateID: candidate.candidateID,
            taskID: config.taskID,
            scalarFitness: fitness,
            rewardAverage: fitness,
            taskPassRate: 1,
            safetyViolationRate: 0,
            holdTimeRatio: 1,
            workerThroughput: Double(workerCount)
        )
    }
}

private struct SlowEvolutionEvaluator: EvolutionCandidateEvaluating {
    let probe: EvaluationConcurrencyProbe

    func evaluateCandidate(request: EvolutionCandidateEvaluationRequest) async throws -> FitnessSummary {
        await probe.enter()
        do {
            try await Task.sleep(nanoseconds: 50_000_000)
            await probe.leave()
        } catch {
            await probe.leave()
            throw error
        }
        let candidateRank = Double(Int(request.candidate.candidateID.split(separator: "c").last ?? "0") ?? 0)
        return FitnessSummary(
            runID: request.config.runID,
            generationIndex: request.candidate.generationIndex,
            candidateID: request.candidate.candidateID,
            taskID: request.config.taskID,
            scalarFitness: candidateRank,
            rewardAverage: candidateRank,
            taskPassRate: 1,
            safetyViolationRate: 0,
            holdTimeRatio: 1,
            workerThroughput: Double(request.workerCount)
        )
    }
}

@MainActor
private final class FakeBatchEvolutionEvaluator: EvolutionCandidateBatchEvaluating {
    private(set) var singleCandidateRequestCount = 0
    private(set) var batchCandidateIDs: [[String]] = []

    func evaluateCandidate(request: EvolutionCandidateEvaluationRequest) async throws -> FitnessSummary {
        singleCandidateRequestCount += 1
        return summary(
            config: request.config,
            candidate: request.candidate,
            workerCount: request.workerCount
        )
    }

    func evaluateCandidates(request: EvolutionCandidateBatchEvaluationRequest) async throws -> [FitnessSummary] {
        batchCandidateIDs.append(request.candidates.map(\.candidateID))
        return request.candidates.map { candidate in
            summary(
                config: request.config,
                candidate: candidate,
                workerCount: request.workerCount
            )
        }
    }

    private func summary(
        config: EvolutionRunConfig,
        candidate: GenomeCandidate,
        workerCount: Int
    ) -> FitnessSummary {
        let candidateRank = Double(Int(candidate.candidateID.split(separator: "c").last ?? "0") ?? 0)
        return FitnessSummary(
            runID: config.runID,
            generationIndex: candidate.generationIndex,
            candidateID: candidate.candidateID,
            taskID: config.taskID,
            scalarFitness: candidateRank,
            rewardAverage: candidateRank,
            taskPassRate: 1,
            safetyViolationRate: 0,
            holdTimeRatio: 1,
            workerThroughput: Double(workerCount)
        )
    }
}

private struct PublishRegressionEvolutionEvaluator: EvolutionCandidateEvaluating {
    func evaluateCandidate(request: EvolutionCandidateEvaluationRequest) async throws -> FitnessSummary {
        let candidateRank = Int(request.candidate.candidateID.split(separator: "c").last ?? "0") ?? 0
        if candidateRank == 0 {
            return FitnessSummary(
                runID: request.config.runID,
                generationIndex: request.candidate.generationIndex,
                candidateID: request.candidate.candidateID,
                taskID: request.config.taskID,
                scalarFitness: 1,
                rewardAverage: 1,
                taskPassRate: 1,
                safetyViolationRate: 0,
                holdTimeRatio: 1,
                noveltyScore: 1,
                workerThroughput: Double(request.workerCount)
            )
        }
        return FitnessSummary(
            runID: request.config.runID,
            generationIndex: request.candidate.generationIndex,
            candidateID: request.candidate.candidateID,
            taskID: request.config.taskID,
            scalarFitness: 10,
            rewardAverage: 10,
            taskPassRate: 0.5,
            safetyViolationRate: 0,
            holdTimeRatio: 1,
            noveltyScore: 1,
            workerThroughput: Double(request.workerCount)
        )
    }
}

private struct DuplicateBehaviorEvolutionEvaluator: EvolutionCandidateEvaluating {
    func evaluateCandidate(request: EvolutionCandidateEvaluationRequest) async throws -> FitnessSummary {
        let candidateRank = Double(Int(request.candidate.candidateID.split(separator: "c").last ?? "0") ?? 0)
        return FitnessSummary(
            runID: request.config.runID,
            generationIndex: request.candidate.generationIndex,
            candidateID: request.candidate.candidateID,
            taskID: request.config.taskID,
            scalarFitness: candidateRank,
            rewardAverage: 1,
            taskPassRate: 1,
            safetyViolationRate: 0,
            holdTimeRatio: 1,
            altitudeErrorRatio: 0.75,
            workerThroughput: Double(request.workerCount),
            behaviorDescriptor: [
                "stableBehavior": 1,
            ]
        )
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
