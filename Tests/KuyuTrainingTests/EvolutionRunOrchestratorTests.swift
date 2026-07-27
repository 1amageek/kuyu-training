import Foundation
import Synchronization
import Testing
@testable import KuyuTraining

@MainActor
@Test func evolutionRunOrchestratorStopsEarlyWhenFitnessAndTaskQualityPlateau() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend(artifactDirectory: directory)
    let evaluator = FakeEvolutionEvaluator(taskPassRate: 1, fixedFitness: 1)
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

    #expect(result.manifest.terminalState == .completed)
    #expect(result.manifest.generationCount == 8)
    #expect(result.generations.count == 3)
    #expect(result.fitness.count == 9)
    #expect(result.manifest.failureReason?.hasPrefix("early-stopped:plateau") == true)
    #expect(backend.nextGenerationRequests.count == 2)

    let artifacts = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
    #expect(artifacts.manifest.failureReason?.hasPrefix("early-stopped:plateau") == true)
    #expect(artifacts.generations.count == 3)
    #expect(artifacts.fitness.count == 9)
}

@MainActor
@Test func evolutionRunOrchestratorWritesAutonomousEvolutionArtifacts() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend(artifactDirectory: directory)
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
    #expect(result.manifest.antitheticSampling == false)
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

    let artifacts = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
    #expect(artifacts.manifest.runID == "evolution-run")
    #expect(artifacts.eliteArchive.bestCandidateID == "g1-c3")
    #expect(artifacts.acceptedCheckpoint.accepted == false)
    #expect(artifacts.acceptedCheckpoint.candidateID == nil)
    #expect(artifacts.acceptedCheckpoint.checkpointURL == nil)
    #expect(artifacts.acceptedCheckpoint.reasons.contains("dedicated-acceptance-required"))
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
@Test func evolutionRunOrchestratorRecordsAntitheticSamplingForPairedPopulation() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let orchestrator = EvolutionRunOrchestrator(
        backend: FakeEvolutionBackend(artifactDirectory: directory),
        evaluator: FakeEvolutionEvaluator()
    )

    let result = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-antithetic",
            taskID: "lift",
            configHash: "config-hash",
            policyID: "manasMLX",
            populationSize: 3,
            generationCount: 1,
            eliteCount: 1,
            workerCount: 1,
            antitheticSampling: true,
            commonRandomSeed: 42,
            mutationRate: 0.08
        ),
        gatePolicy: strictEvolutionGatePolicy(),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .completed)
    #expect(result.manifest.antitheticSampling)
    let pairedCandidates = result.candidates.filter { $0.antitheticPairID != nil }
    #expect(pairedCandidates.count == 2)
    #expect(Set(pairedCandidates.map(\.antitheticPairID)) == ["g0-p0"])
    #expect(Set(pairedCandidates.compactMap(\.antitheticSign)) == [1, -1])

    let artifacts = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
    #expect(artifacts.manifest.antitheticSampling)
}

@MainActor
@Test func evolutionRunOrchestratorRejectsAntitheticPopulationWithoutCompletePairs() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let orchestrator = EvolutionRunOrchestrator(
        backend: FakeEvolutionBackend(artifactDirectory: directory),
        evaluator: FakeEvolutionEvaluator()
    )

    let result = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-antithetic-unpaired",
            taskID: "lift",
            configHash: "config-hash",
            policyID: "manasMLX",
            populationSize: 4,
            generationCount: 1,
            eliteCount: 1,
            workerCount: 1,
            antitheticSampling: true,
            commonRandomSeed: 42,
            mutationRate: 0.08
        ),
        gatePolicy: strictEvolutionGatePolicy(),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .failed)
    let reason = try #require(result.manifest.failureReason)
    #expect(reason.contains("invalid-evolution-config"))
    #expect(reason.contains("invalidAntitheticPopulationSize(4)"))
    #expect(result.candidates.isEmpty)
}

@MainActor
@Test func qualityDiversityResumeIgnoresPreviouslyPrunedGateFailures() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let config = EvolutionRunConfig(
        runID: "evolution-qd-resume-retention",
        taskID: "lift",
        configHash: "config-hash",
        policyID: "manasMLX",
        populationSize: 3,
        generationCount: 2,
        eliteCount: 1,
        workerCount: 1,
        searchStrategy: .qualityDiversity,
        mutationRate: 0.08
    )
    let gatePolicy = strictEvolutionGatePolicy()
    let initialBackend = FakeEvolutionBackend(artifactDirectory: directory)
    let initialRun = await EvolutionRunOrchestrator(
        backend: initialBackend,
        evaluator: FakeEvolutionEvaluator(unsafeCandidateID: "g0-c2"),
        candidateArtifactRetainer: EvolutionCompactCandidateArtifactRetainer()
    ).run(
        config: config,
        gatePolicy: gatePolicy,
        artifactDirectory: directory
    )
    #expect(initialRun.manifest.terminalState == .completed)
    let prunedCandidate = try #require(initialRun.candidates.first {
        $0.candidateID == "g0-c2"
    })
    #expect(prunedCandidate.checkpointURL.map {
        !FileManager.default.fileExists(atPath: $0.path)
    } == true)

    let store = EvolutionResumeCheckpointStore()
    let resume = try store.loadResumeState(
        in: directory,
        upToGeneration: 0,
        expectedConfigHash: config.configHash
    )
    let resumed = await EvolutionRunOrchestrator(
        backend: FakeEvolutionBackend(artifactDirectory: directory),
        evaluator: FakeEvolutionEvaluator(unsafeCandidateID: "g0-c2"),
        candidateArtifactRetainer: EvolutionCompactCandidateArtifactRetainer()
    ).run(
        config: config,
        gatePolicy: gatePolicy,
        artifactDirectory: directory,
        resumeFrom: resume
    )

    #expect(resumed.manifest.terminalState == .completed)
    #expect(resumed.manifest.failureReason?.contains("candidate-artifact-retention") != true)
}

@MainActor
@Test func evolutionRunOrchestratorRejectsSearchWinnerWhenDedicatedAcceptanceFails() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let acceptanceEvaluator = FakeEvolutionAcceptanceEvaluator(taskPassRate: 0)
    let orchestrator = EvolutionRunOrchestrator(
        backend: FakeEvolutionBackend(artifactDirectory: directory),
        evaluator: FakeEvolutionEvaluator(),
        candidateAcceptanceStage: EvolutionCandidateAcceptanceStage(
            evaluator: acceptanceEvaluator,
            gatePolicy: strictEvolutionGatePolicy()
        )
    )

    let result = await orchestrator.run(
        config: acceptanceEvolutionConfig(
            runID: "evolution-acceptance-rejected",
            generationCount: 3
        ),
        gatePolicy: strictEvolutionGatePolicy(),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .rejected)
    #expect(result.manifest.candidateAcceptanceMode == .dedicatedEvaluation)
    #expect(result.fitness.count == 9)
    #expect(result.acceptanceEvaluations.count == 1)
    #expect(result.acceptanceEvaluations.first?.candidateID == "g2-c2")
    #expect(result.acceptanceEvaluations.first?.accepted == false)
    #expect(result.generations.count == 3)
    #expect(result.generations.allSatisfy { $0.accepted })
    #expect(result.manifest.failureReason?.contains("acceptance:task-pass-rate-below-min:g2-c2") == true)
    #expect(acceptanceEvaluator.requests.count == 1)
    #expect(acceptanceEvaluator.requests.first?.searchFitness.candidateID == "g2-c2")

    let artifacts = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
    #expect(artifacts.acceptanceEvaluations.count == result.acceptanceEvaluations.count)
    #expect(artifacts.acceptanceEvaluations.first?.candidateID == result.acceptanceEvaluations.first?.candidateID)
    #expect(artifacts.acceptanceEvaluations.first?.fitness == result.acceptanceEvaluations.first?.fitness)
    #expect(artifacts.acceptanceEvaluations.first?.accepted == result.acceptanceEvaluations.first?.accepted)
    #expect(
        artifacts.acceptanceEvaluations.first?.rejectionReasons
            == result.acceptanceEvaluations.first?.rejectionReasons
    )
    #expect(artifacts.acceptedCheckpoint.accepted == false)
}

@MainActor
@Test func evolutionRunOrchestratorPublishesSearchWinnerAfterDedicatedAcceptancePasses() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let acceptanceEvaluator = FakeEvolutionAcceptanceEvaluator(taskPassRate: 1)
    let orchestrator = EvolutionRunOrchestrator(
        backend: FakeEvolutionBackend(artifactDirectory: directory),
        evaluator: FakeEvolutionEvaluator(),
        candidateAcceptanceStage: EvolutionCandidateAcceptanceStage(
            evaluator: acceptanceEvaluator,
            gatePolicy: strictEvolutionGatePolicy()
        )
    )

    let result = await orchestrator.run(
        config: acceptanceEvolutionConfig(
            runID: "evolution-acceptance-passed",
            generationCount: 3
        ),
        gatePolicy: strictEvolutionGatePolicy(),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .completed)
    #expect(result.fitness.count == 9)
    #expect(result.acceptanceEvaluations.count == 1)
    #expect(result.acceptanceEvaluations.first?.candidateID == "g2-c2")
    #expect(result.acceptanceEvaluations.first?.accepted == true)
    #expect(result.acceptanceEvaluations.first?.incumbentCandidateID == "g0-c0")
    #expect(result.acceptanceEvaluations.first?.incumbentFitness.candidateID == "g0-c0")
    #expect(result.acceptanceEvaluations.first?.incumbentCheckpointReference.checkpointID == "checkpoint-g0-c0")
    #expect(result.generations.count == 3)
    #expect(result.generations.allSatisfy { $0.accepted })
    #expect(acceptanceEvaluator.requests.count == 1)

    let artifacts = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
    #expect(artifacts.fitness.count == 9)
    #expect(artifacts.acceptanceEvaluations.count == 1)
    #expect(artifacts.acceptedCheckpoint.accepted)
    #expect(artifacts.acceptedCheckpoint.candidateID == "g2-c2")
    #expect(artifacts.acceptanceEvaluations[0].evaluationContract.evaluatorID == "FakeEvolutionAcceptanceEvaluator")
    #expect(artifacts.acceptanceEvaluations[0].evidence.count == 1)
    _ = try EvolutionAcceptanceEvidenceIntegrity().validatedURL(
        for: artifacts.acceptanceEvaluations[0].evidence[0],
        in: directory.appendingPathComponent("acceptance", isDirectory: true)
    )
}

@MainActor
@Test func evolutionRunOrchestratorRejectsHeldOutRegressionAgainstIncumbent() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let orchestrator = EvolutionRunOrchestrator(
        backend: FakeEvolutionBackend(artifactDirectory: directory),
        evaluator: FakeEvolutionEvaluator(),
        candidateAcceptanceStage: EvolutionCandidateAcceptanceStage(
            evaluator: FakeEvolutionAcceptanceEvaluator(
                taskPassRate: 1,
                incumbentScalarFitness: 30
            ),
            gatePolicy: EvolutionGatePolicy(
                eliteCount: 1,
                minimumTaskPassRate: 1,
                maximumSafetyViolationRate: 0,
                minimumHoldTimeRatio: 1,
                minimumImprovementOverIncumbent: 0
            )
        )
    )

    let result = await orchestrator.run(
        config: acceptanceEvolutionConfig(
            runID: "evolution-held-out-incumbent-regression",
            generationCount: 3
        ),
        gatePolicy: strictEvolutionGatePolicy(),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .rejected)
    let record = try #require(result.acceptanceEvaluations.first)
    #expect(record.fitness.scalarFitness == 22)
    #expect(record.incumbentFitness.scalarFitness == 30)
    #expect(record.rejectionReasons.contains { $0.hasPrefix("incumbent-improvement-below-min:") })
    #expect(record.rejectionReasons.contains { $0.hasPrefix("acceptance-metric-regression:rewardAverage:") })
    #expect(try EvolutionRunArtifactValidator().validatedBundle(in: directory).acceptedCheckpoint.accepted == false)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func evolutionRunOrchestratorForwardsTypedWorkProgressToDedicatedAcceptance() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let reporter = RecordingTrainingProgressReporter()
    let orchestrator = EvolutionRunOrchestrator(
        backend: FakeEvolutionBackend(artifactDirectory: directory),
        evaluator: FakeEvolutionEvaluator(),
        candidateAcceptanceStage: EvolutionCandidateAcceptanceStage(
            evaluator: FakeEvolutionAcceptanceEvaluator(taskPassRate: 1),
            gatePolicy: strictEvolutionGatePolicy()
        )
    )

    let result = await orchestrator.run(
        config: acceptanceEvolutionConfig(runID: "evolution-acceptance-progress"),
        gatePolicy: strictEvolutionGatePolicy(),
        artifactDirectory: directory,
        progressReporter: reporter
    )

    let records = await reporter.records()
    #expect(result.manifest.terminalState == .completed)
    #expect(records.count == 1)
    #expect(records.first?.phase == .candidateGate)
    #expect(records.first?.scope.candidateID == "g0-c2")
}

@MainActor
@Test func evolutionRunArtifactValidatorRejectsTamperedAcceptanceEvidence() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let orchestrator = EvolutionRunOrchestrator(
        backend: FakeEvolutionBackend(artifactDirectory: directory),
        evaluator: FakeEvolutionEvaluator(),
        candidateAcceptanceStage: EvolutionCandidateAcceptanceStage(
            evaluator: FakeEvolutionAcceptanceEvaluator(taskPassRate: 1),
            gatePolicy: strictEvolutionGatePolicy()
        )
    )

    let result = await orchestrator.run(
        config: acceptanceEvolutionConfig(runID: "evolution-acceptance-tampered"),
        gatePolicy: strictEvolutionGatePolicy(),
        artifactDirectory: directory
    )
    #expect(result.manifest.terminalState == .completed)
    let evidence = try #require(result.acceptanceEvaluations.first?.evidence.first)
    let evidenceURL = directory
        .appendingPathComponent("acceptance", isDirectory: true)
        .appendingPathComponent(evidence.relativePath, isDirectory: false)
    try Data("tampered-evidence".utf8).write(to: evidenceURL, options: [.atomic])

    #expect(throws: EvolutionRunArtifactValidator.ValidationError.self) {
        _ = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
    }
}

@MainActor
@Test func evolutionRunArtifactValidatorRejectsTamperedAcceptedCheckpoint() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let orchestrator = EvolutionRunOrchestrator(
        backend: FakeEvolutionBackend(artifactDirectory: directory),
        evaluator: FakeEvolutionEvaluator(),
        candidateAcceptanceStage: EvolutionCandidateAcceptanceStage(
            evaluator: FakeEvolutionAcceptanceEvaluator(taskPassRate: 1),
            gatePolicy: strictEvolutionGatePolicy()
        )
    )

    let result = await orchestrator.run(
        config: acceptanceEvolutionConfig(runID: "evolution-checkpoint-tampered"),
        gatePolicy: strictEvolutionGatePolicy(),
        artifactDirectory: directory
    )
    #expect(result.manifest.terminalState == .completed)
    let checkpointURL = try #require(result.acceptanceEvaluations.first?.checkpointReference.checkpointURL)
    try Data("replaced-checkpoint".utf8).write(
        to: checkpointURL.appendingPathComponent("manifest.json"),
        options: [.atomic]
    )

    #expect(throws: EvolutionRunArtifactValidator.ValidationError.invalidCheckpointReference(
        candidateID: "g0-c2",
        reason: "referenceMismatch(\"checkpoint-g0-c2\")"
    )) {
        _ = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
    }
}

@MainActor
@Test func evolutionRunOrchestratorRejectsCheckpointMutationDuringAcceptance() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let orchestrator = EvolutionRunOrchestrator(
        backend: FakeEvolutionBackend(artifactDirectory: directory),
        evaluator: FakeEvolutionEvaluator(),
        candidateAcceptanceStage: EvolutionCandidateAcceptanceStage(
            evaluator: FakeEvolutionAcceptanceEvaluator(
                taskPassRate: 1,
                evidenceMode: .mutateCheckpoint
            ),
            gatePolicy: strictEvolutionGatePolicy()
        )
    )

    let result = await orchestrator.run(
        config: acceptanceEvolutionConfig(runID: "evolution-checkpoint-mutated-during-acceptance"),
        gatePolicy: strictEvolutionGatePolicy(),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .failed)
    #expect(result.manifest.failureReason?.contains("referenceMismatch") == true)
    #expect(result.acceptanceEvaluations.isEmpty)
}

@MainActor
@Test func evolutionRunOrchestratorRejectsAcceptanceEvidencePathTraversal() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let orchestrator = EvolutionRunOrchestrator(
        backend: FakeEvolutionBackend(artifactDirectory: directory),
        evaluator: FakeEvolutionEvaluator(),
        candidateAcceptanceStage: EvolutionCandidateAcceptanceStage(
            evaluator: FakeEvolutionAcceptanceEvaluator(
                taskPassRate: 1,
                evidenceMode: .pathTraversal
            ),
            gatePolicy: strictEvolutionGatePolicy()
        )
    )

    let result = await orchestrator.run(
        config: acceptanceEvolutionConfig(runID: "evolution-acceptance-path-traversal"),
        gatePolicy: strictEvolutionGatePolicy(),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .failed)
    #expect(result.manifest.failureReason?.contains("invalidRelativePath") == true)
    #expect(result.acceptanceEvaluations.isEmpty)
    let artifacts = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
    #expect(artifacts.acceptedCheckpoint.accepted == false)
}

@MainActor
@Test func evolutionRunOrchestratorSkipsDedicatedAcceptanceWhenSearchGateRejectsAllCandidates() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let acceptanceEvaluator = FakeEvolutionAcceptanceEvaluator(taskPassRate: 1)
    let orchestrator = EvolutionRunOrchestrator(
        backend: FakeEvolutionBackend(artifactDirectory: directory),
        evaluator: FakeEvolutionEvaluator(taskPassRate: 0),
        candidateAcceptanceStage: EvolutionCandidateAcceptanceStage(
            evaluator: acceptanceEvaluator,
            gatePolicy: strictEvolutionGatePolicy()
        )
    )

    let result = await orchestrator.run(
        config: acceptanceEvolutionConfig(runID: "evolution-search-rejected"),
        gatePolicy: strictEvolutionGatePolicy(),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .rejected)
    #expect(result.acceptanceEvaluations.isEmpty)
    #expect(acceptanceEvaluator.requests.isEmpty)

    let artifacts = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
    #expect(artifacts.acceptanceEvaluations.isEmpty)
    #expect(artifacts.acceptedCheckpoint.accepted == false)
}

@MainActor
@Test func evolutionRunOrchestratorFailsClosedWhenAcceptanceReturnsAnotherCandidate() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let acceptanceEvaluator = FakeEvolutionAcceptanceEvaluator(
        taskPassRate: 1,
        returnedCandidateID: "unexpected-candidate"
    )
    let orchestrator = EvolutionRunOrchestrator(
        backend: FakeEvolutionBackend(artifactDirectory: directory),
        evaluator: FakeEvolutionEvaluator(),
        candidateAcceptanceStage: EvolutionCandidateAcceptanceStage(
            evaluator: acceptanceEvaluator,
            gatePolicy: strictEvolutionGatePolicy()
        )
    )

    let result = await orchestrator.run(
        config: acceptanceEvolutionConfig(runID: "evolution-acceptance-identity-mismatch"),
        gatePolicy: strictEvolutionGatePolicy(),
        artifactDirectory: directory
    )

    #expect(result.manifest.terminalState == .failed)
    #expect(result.manifest.failureReason?.hasPrefix("evolution-acceptance-failed:") == true)
    #expect(result.manifest.failureReason?.contains("identity-mismatch") == true)
    #expect(result.acceptanceEvaluations.isEmpty)
    #expect(acceptanceEvaluator.requests.count == 1)

    let artifacts = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
    #expect(artifacts.manifest.terminalState == .failed)
    #expect(artifacts.acceptanceEvaluations.isEmpty)
    #expect(artifacts.acceptedCheckpoint.accepted == false)
}

@MainActor
@Test func evolutionRunOrchestratorEvaluatesCandidatesConcurrently() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend(artifactDirectory: directory)
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
            generationCount: 3,
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
    let backend = FakeEvolutionBackend(artifactDirectory: directory)
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
@Test func evolutionPopulationBatchTraceUsesTaskConcurrency() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let evaluator = FakePopulationBatchEvolutionEvaluator()
    let orchestrator = EvolutionRunOrchestrator(
        backend: FakeEvolutionBackend(artifactDirectory: directory),
        evaluator: evaluator
    )

    let result = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-population-batch-trace",
            taskID: "lift",
            configHash: "config-hash",
            policyID: "manasMLX",
            populationSize: 2,
            generationCount: 1,
            eliteCount: 1,
            workerCount: 1,
            candidateEvaluationConcurrency: 1,
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
    #expect(evaluator.batchCandidateIDs == [["g0-c0", "g0-c1"]])
    #expect(result.evaluationTraces.allSatisfy { trace in
        trace.requestedConcurrency == 1 && trace.activeEvaluationCountAtStart == 1
    })
    _ = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func evolutionRunOrchestratorForwardsTypedWorkProgressToBatchEvaluator() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let evaluator = FakeBatchEvolutionEvaluator()
    let reporter = RecordingTrainingProgressReporter()
    let orchestrator = EvolutionRunOrchestrator(
        backend: FakeEvolutionBackend(artifactDirectory: directory),
        evaluator: evaluator
    )

    let result = await orchestrator.run(
        config: EvolutionRunConfig(
            runID: "evolution-work-progress",
            taskID: "lift",
            configHash: "config-hash",
            policyID: "manasMLX",
            populationSize: 5,
            generationCount: 1,
            eliteCount: 1,
            workerCount: 2,
            candidateEvaluationConcurrency: 2,
            mutationRate: 0.08
        ),
        artifactDirectory: directory,
        progressReporter: reporter
    )

    let records = await reporter.records()
    #expect(result.manifest.terminalState == .completed)
    #expect(records.count == 3)
    #expect(records.map(\.scope.runID) == Array(repeating: "evolution-work-progress", count: 3))
    #expect(records.map(\.phase) == Array(repeating: .rollout, count: 3))
    #expect(records.map(\.unit.identifier) == ["g0-c0", "g0-c2", "g0-c4"])
}

@MainActor
@Test func evolutionRunOrchestratorStreamsCandidateEventsBeforeGenerationCompletion() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend(artifactDirectory: directory)
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
    let backend = FakeEvolutionBackend(artifactDirectory: directory)
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

    let artifacts = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
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
    let backend = FakeEvolutionBackend(artifactDirectory: directory)
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
    let backend = FakeEvolutionBackend(artifactDirectory: directory)
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
    #expect(result.generations.count == 1)
    #expect(backend.nextGenerationRequests.isEmpty)
    #expect(result.generations.first?.accepted == false)
    #expect(result.generations.first?.bestCandidateID == nil)
    #expect(result.generations.first?.bestFitness == nil)
    #expect(result.generations.first?.rejectionReasons.contains("no-candidate-passed-gate") == true)
    #expect(result.generations.first?.rejectionReasons.contains { $0.hasPrefix("task-pass-rate-below-min:g0-c") } == true)
    #expect(result.eliteArchive.eliteCandidateIDs.isEmpty)

    let artifacts = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
    #expect(artifacts.manifest.terminalState == .rejected)
    #expect(!artifacts.acceptedCheckpoint.accepted)
    #expect(artifacts.acceptedCheckpoint.candidateID == nil)
}

@MainActor
@Test func evolutionRunOrchestratorRejectsLowNoveltyCandidatesWhenRequired() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend(artifactDirectory: directory)
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
    let backend = FakeEvolutionBackend(artifactDirectory: directory)
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
    let backend = FakeEvolutionBackend(artifactDirectory: directory)
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

    let artifacts = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
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
    let backend = FakeEvolutionBackend(artifactDirectory: directory)
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

    let artifacts = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
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
    let backend = FakeEvolutionBackend(artifactDirectory: directory)
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

    let artifacts = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
    #expect(artifacts.manifest.terminalState == .completed)
    #expect(artifacts.eliteArchive.bestCandidateID == "g0-c2")
}

@MainActor
@Test func evolutionArtifactValidatorRejectsNonFiniteFitness() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend(artifactDirectory: directory)
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
        _ = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
        Issue.record("Expected evolution artifact validator to reject non-finite fitness")
    } catch let error as EvolutionRunArtifactValidator.ValidationError {
        #expect(error == .nonFiniteFitness(candidateID: "g0-c1"))
    }
}

@MainActor
@Test func evolutionArtifactValidatorRejectsTamperedQualityDiversityArchive() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let backend = FakeEvolutionBackend(artifactDirectory: directory)
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
        _ = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
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
    let backend = FakeEvolutionBackend(artifactDirectory: directory)
    let evaluator = FakeEvolutionEvaluator()
    // Drive the generic TypedTrainingBackend contract end-to-end through the real
    // legacy→typed adapter, proving the typed layer is functional and connected to the
    // production backend protocols (not orphan scaffolding).
    let typed = EvolutionTypedBackendAdapter(
        config: config,
        backend: backend,
        evaluator: evaluator,
        publicationValidator: TestModelBundlePublicationValidator()
    )

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
    let firstCheckpointURL = try #require(firstCandidate.checkpointURL)
    try FileManager.default.createDirectory(at: firstCheckpointURL, withIntermediateDirectories: true)
    try "checkpoint".write(
        to: firstCheckpointURL.appendingPathComponent("manifest.json", isDirectory: false),
        atomically: true,
        encoding: .utf8
    )
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

    let destinationURL = directory.appendingPathComponent("published", isDirectory: true)
        .appendingPathComponent("accepted.manasbundle", isDirectory: true)
    let destination = ModelBundleReference(bundleID: "accepted", kind: .accepted, url: destinationURL)
    let publicationReference = try EvolutionCheckpointIntegrity().reference(
        checkpointID: firstCandidate.candidateID,
        checkpointURL: firstCheckpointURL,
        artifactRoot: directory
    )
    let published = try await typed.publish(firstCandidate, request: CheckpointPublicationRequest(
        runID: config.runID,
        candidateID: firstCandidate.candidateID,
        expectedSourceDigest: publicationReference.sha256Digest,
        destination: destination,
        artifactRoot: directory
    ))
    #expect(published.kind == .accepted)
    #expect(published.url.standardizedFileURL == destinationURL.standardizedFileURL)
    #expect(FileManager.default.fileExists(
        atPath: destinationURL.appendingPathComponent("manifest.json", isDirectory: false).path
    ))
}

@MainActor
@Test func typedTrainingBackendAdapterRejectsPublicationOutsideArtifactRoot() async throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let config = EvolutionRunConfig(
        runID: "typed-evolution-publish-boundary",
        taskID: "lift",
        configHash: "config-hash",
        policyID: "manasMLX",
        populationSize: 1,
        generationCount: 1,
        eliteCount: 1,
        workerCount: 1,
        mutationRate: 0.01
    )
    let backend = FakeEvolutionBackend(artifactDirectory: directory)
    let typed = EvolutionTypedBackendAdapter(
        config: config,
        backend: backend,
        evaluator: FakeEvolutionEvaluator(),
        publicationValidator: TestModelBundlePublicationValidator()
    )
    let source = ModelBundleReference(
        bundleID: "source",
        kind: .source,
        url: directory.appendingPathComponent("source.manasbundle", isDirectory: true)
    )
    let candidates = try await typed.seedPopulation(
        from: try await typed.loadCheckpoint(source),
        request: PopulationSeedRequest(runID: config.runID, populationSize: 1, seed: 42, artifactRoot: directory)
    )
    let candidate = try #require(candidates.first)
    let checkpointURL = try #require(candidate.checkpointURL)
    try FileManager.default.createDirectory(at: checkpointURL, withIntermediateDirectories: true)

    let outsideDestination = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-publish-outside-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("accepted.manasbundle", isDirectory: true)
    let destination = ModelBundleReference(bundleID: "accepted", kind: .accepted, url: outsideDestination)
    do {
        _ = try await typed.publish(candidate, request: CheckpointPublicationRequest(
            runID: config.runID,
            candidateID: candidate.candidateID,
            expectedSourceDigest: String(repeating: "0", count: 64),
            destination: destination,
            artifactRoot: directory
        ))
        Issue.record("Expected publication outside artifact root to be rejected.")
    } catch ModelBundlePublicationStore.PublicationError.pathOutsideArtifactRoot(
        let role,
        let path,
        let root
    ) {
        #expect(role == "destination")
        #expect(path == outsideDestination.standardizedFileURL.path)
        #expect(root == directory.standardizedFileURL.path)
    }
}

@MainActor
@Test func modelBundlePublicationStoreRejectsSourceThroughSymlinkedArtifactChild() throws {
    let directory = try evolutionTemporaryDirectory()
    let external = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-evolution-source-symlink-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
    defer {
        evolutionCleanup(directory)
        evolutionCleanup(external)
    }

    let linkedSources = directory.appendingPathComponent("linked-sources", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: linkedSources, withDestinationURL: external)
    let realSource = external.appendingPathComponent("candidate.manasbundle", isDirectory: true)
    try FileManager.default.createDirectory(at: realSource, withIntermediateDirectories: true)
    let sourceThroughLink = linkedSources.appendingPathComponent("candidate.manasbundle", isDirectory: true)
    let destination = directory.appendingPathComponent("published", isDirectory: true)
        .appendingPathComponent("accepted.manasbundle", isDirectory: true)
    let request = CheckpointPublicationRequest(
        runID: "source-symlink",
        candidateID: "candidate",
        expectedSourceDigest: String(repeating: "0", count: 64),
        destination: ModelBundleReference(bundleID: "accepted", kind: .accepted, url: destination),
        artifactRoot: directory
    )

    do {
        _ = try ModelBundlePublicationStore(
            validator: TestModelBundlePublicationValidator()
        ).publish(source: sourceThroughLink, request: request)
        Issue.record("Expected publication source through symlinked artifact child to be rejected.")
    } catch ModelBundlePublicationStore.PublicationError.pathOutsideArtifactRoot(
        let role,
        let path,
        let root
    ) {
        #expect(role == "source")
        #expect(path == realSource.standardizedFileURL.resolvingSymlinksInPath().path)
        #expect(root == directory.standardizedFileURL.resolvingSymlinksInPath().path)
    }
}

@MainActor
@Test func modelBundlePublicationStoreRejectsDestinationThroughSymlinkedArtifactChild() throws {
    let directory = try evolutionTemporaryDirectory()
    let external = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-evolution-destination-symlink-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
    defer {
        evolutionCleanup(directory)
        evolutionCleanup(external)
    }

    let source = directory.appendingPathComponent("candidate.manasbundle", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let linkedDestinationRoot = directory.appendingPathComponent("linked-published", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: linkedDestinationRoot, withDestinationURL: external)
    let destination = linkedDestinationRoot.appendingPathComponent("accepted.manasbundle", isDirectory: true)
    let request = CheckpointPublicationRequest(
        runID: "destination-symlink",
        candidateID: "candidate",
        expectedSourceDigest: String(repeating: "0", count: 64),
        destination: ModelBundleReference(bundleID: "accepted", kind: .accepted, url: destination),
        artifactRoot: directory
    )

    do {
        _ = try ModelBundlePublicationStore(
            validator: TestModelBundlePublicationValidator()
        ).publish(source: source, request: request)
        Issue.record("Expected publication destination through symlinked artifact child to be rejected.")
    } catch ModelBundlePublicationStore.PublicationError.pathOutsideArtifactRoot(
        let role,
        let path,
        let root
    ) {
        #expect(role == "destinationParent")
        #expect(path == linkedDestinationRoot.standardizedFileURL.resolvingSymlinksInPath().path)
        #expect(root == directory.standardizedFileURL.resolvingSymlinksInPath().path)
    }
    #expect(!FileManager.default.fileExists(
        atPath: external.appendingPathComponent("accepted.manasbundle", isDirectory: true).path
    ))
}

@MainActor
@Test func modelBundlePublicationStoreRejectsUnacceptedSourceDigest() throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let source = directory.appendingPathComponent("candidate.manasbundle", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data("valid-manifest".utf8).write(
        to: source.appendingPathComponent("manifest.json"),
        options: [.atomic]
    )
    let destination = directory
        .appendingPathComponent("published", isDirectory: true)
        .appendingPathComponent("accepted.manasbundle", isDirectory: true)
    let expectedDigest = String(repeating: "0", count: 64)
    let request = CheckpointPublicationRequest(
        runID: "digest-mismatch",
        candidateID: "candidate",
        expectedSourceDigest: expectedDigest,
        destination: ModelBundleReference(bundleID: "accepted", kind: .accepted, url: destination),
        artifactRoot: directory
    )

    do {
        _ = try ModelBundlePublicationStore(
            validator: TestModelBundlePublicationValidator()
        ).publish(source: source, request: request)
        Issue.record("Expected an unaccepted source digest to be rejected.")
    } catch ModelBundlePublicationStore.PublicationError.sourceDigestMismatch(let expected, let actual) {
        #expect(expected == expectedDigest)
        #expect(actual != expected)
    }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
}

@MainActor
@Test func modelBundlePublicationStoreRejectsSemanticallyInvalidBundle() throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let source = directory.appendingPathComponent("candidate.manasbundle", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data("not-a-bundle".utf8).write(
        to: source.appendingPathComponent("weights.bin"),
        options: [.atomic]
    )
    let reference = try EvolutionCheckpointIntegrity().reference(
        checkpointID: "candidate",
        checkpointURL: source,
        artifactRoot: directory
    )
    let destination = directory
        .appendingPathComponent("published", isDirectory: true)
        .appendingPathComponent("accepted.manasbundle", isDirectory: true)
    let request = CheckpointPublicationRequest(
        runID: "invalid-bundle",
        candidateID: "candidate",
        expectedSourceDigest: reference.sha256Digest,
        destination: ModelBundleReference(bundleID: "accepted", kind: .accepted, url: destination),
        artifactRoot: directory
    )

    do {
        _ = try ModelBundlePublicationStore(
            validator: TestModelBundlePublicationValidator()
        ).publish(source: source, request: request)
        Issue.record("Expected a semantically invalid bundle to be rejected.")
    } catch ModelBundlePublicationStore.PublicationError.bundleValidationFailed(let path, let reason) {
        #expect(path == source.path)
        #expect(!reason.isEmpty)
    }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
}

@MainActor
@Test func modelBundlePublicationStoreRejectsNestedSourceSymlink() throws {
    let directory = try evolutionTemporaryDirectory()
    let external = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-evolution-nested-symlink-\(UUID().uuidString)")
    try Data("external".utf8).write(to: external, options: [.atomic])
    defer {
        evolutionCleanup(directory)
        do {
            try FileManager.default.removeItem(at: external)
        } catch {
            Issue.record("Failed to clean nested symlink fixture: \(error)")
        }
    }
    let source = directory.appendingPathComponent("candidate.manasbundle", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data("valid-manifest".utf8).write(
        to: source.appendingPathComponent("manifest.json"),
        options: [.atomic]
    )
    try FileManager.default.createSymbolicLink(
        at: source.appendingPathComponent("weights.bin"),
        withDestinationURL: external
    )
    let destination = directory
        .appendingPathComponent("published", isDirectory: true)
        .appendingPathComponent("accepted.manasbundle", isDirectory: true)
    let request = CheckpointPublicationRequest(
        runID: "nested-symlink",
        candidateID: "candidate",
        expectedSourceDigest: String(repeating: "0", count: 64),
        destination: ModelBundleReference(bundleID: "accepted", kind: .accepted, url: destination),
        artifactRoot: directory
    )

    do {
        _ = try ModelBundlePublicationStore(
            validator: TestModelBundlePublicationValidator()
        ).publish(source: source, request: request)
        Issue.record("Expected nested source symlink to be rejected.")
    } catch ModelBundlePublicationStore.PublicationError.checkpointIntegrityFailed(let path, let reason) {
        #expect(path == source.path)
        #expect(reason.contains("symbolicLink"))
    }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
}

@MainActor
@Test func modelBundlePublicationStorePreservesDestinationWhenTemporaryValidationFails() throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let source = directory.appendingPathComponent("candidate.manasbundle", isDirectory: true)
    let destination = directory
        .appendingPathComponent("published", isDirectory: true)
        .appendingPathComponent("accepted.manasbundle", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try Data("new".utf8).write(
        to: source.appendingPathComponent("manifest.json", isDirectory: false),
        options: [.atomic]
    )
    try Data("previous".utf8).write(
        to: destination.appendingPathComponent("manifest.json", isDirectory: false),
        options: [.atomic]
    )
    let sourceReference = try EvolutionCheckpointIntegrity().reference(
        checkpointID: "candidate",
        checkpointURL: source,
        artifactRoot: directory
    )
    let request = CheckpointPublicationRequest(
        runID: "temporary-validation-failure",
        candidateID: "candidate",
        expectedSourceDigest: sourceReference.sha256Digest,
        destination: ModelBundleReference(
            bundleID: "accepted",
            kind: .accepted,
            url: destination,
            contentHash: sourceReference.sha256Digest
        ),
        artifactRoot: directory
    )

    #expect(throws: ModelBundlePublicationStore.PublicationError.self) {
        _ = try ModelBundlePublicationStore(
            validator: FailingTemporaryPublicationValidator()
        ).publish(source: source, request: request)
    }
    let preserved = try String(
        contentsOf: destination.appendingPathComponent("manifest.json", isDirectory: false),
        encoding: .utf8
    )
    #expect(preserved == "previous")
    let residue = try FileManager.default.contentsOfDirectory(
        at: destination.deletingLastPathComponent(),
        includingPropertiesForKeys: nil
    ).filter {
        $0.lastPathComponent.contains(".publishing") || $0.lastPathComponent.contains(".rollback")
    }
    #expect(residue.isEmpty)
}

@MainActor
@Test func modelBundlePublicationStoreRestoresPreviousDestinationAfterFinalValidationFailure() throws {
    let directory = try evolutionTemporaryDirectory()
    defer { evolutionCleanup(directory) }
    let source = directory.appendingPathComponent("candidate.manasbundle", isDirectory: true)
    let destination = directory
        .appendingPathComponent("published", isDirectory: true)
        .appendingPathComponent("accepted.manasbundle", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try Data("new".utf8).write(
        to: source.appendingPathComponent("manifest.json", isDirectory: false),
        options: [.atomic]
    )
    try Data("previous".utf8).write(
        to: destination.appendingPathComponent("manifest.json", isDirectory: false),
        options: [.atomic]
    )
    let sourceReference = try EvolutionCheckpointIntegrity().reference(
        checkpointID: "candidate",
        checkpointURL: source,
        artifactRoot: directory
    )
    let request = CheckpointPublicationRequest(
        runID: "transactional-publication",
        candidateID: "candidate",
        expectedSourceDigest: sourceReference.sha256Digest,
        destination: ModelBundleReference(
            bundleID: "accepted",
            kind: .accepted,
            url: destination,
            contentHash: sourceReference.sha256Digest
        ),
        artifactRoot: directory
    )

    #expect(throws: ModelBundlePublicationStore.PublicationError.self) {
        _ = try ModelBundlePublicationStore(
            validator: FailingFinalPublicationValidator()
        ).publish(source: source, request: request)
    }
    let restored = try String(
        contentsOf: destination.appendingPathComponent("manifest.json", isDirectory: false),
        encoding: .utf8
    )
    #expect(restored == "previous")
    let residue = try FileManager.default.contentsOfDirectory(
        at: destination.deletingLastPathComponent(),
        includingPropertiesForKeys: nil
    ).filter {
        $0.lastPathComponent.contains(".publishing") || $0.lastPathComponent.contains(".rollback")
    }
    #expect(residue.isEmpty)
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
        try await evaluateCandidates(request: request, progressReporter: nil)
    }

    func evaluateCandidates(
        request: EvolutionCandidateBatchEvaluationRequest,
        progressReporter: (any TrainingProgressReporting)?
    ) async throws -> [FitnessSummary] {
        batchCandidateIDs.append(request.candidates.map(\.candidateID))
        if let progressReporter, let first = request.candidates.first {
            try await progressReporter.report(TrainingWorkProgress(
                scope: TrainingWorkScope(
                    runID: request.config.runID,
                    generationIndex: first.generationIndex
                ),
                phase: .rollout,
                state: .started,
                unit: TrainingWorkUnit(kind: .candidate, identifier: first.candidateID),
                completedUnitCount: 0,
                totalUnitCount: request.candidates.count,
                populationSize: request.candidates.count
            ))
        }
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

@MainActor
private final class FakePopulationBatchEvolutionEvaluator: EvolutionPopulationBatchEvaluating {
    private(set) var batchCandidateIDs: [[String]] = []

    func evaluateCandidate(request: EvolutionCandidateEvaluationRequest) async throws -> FitnessSummary {
        summary(
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

private actor RecordingTrainingProgressReporter: TrainingProgressReporting {
    private var reportedProgress: [TrainingWorkProgress] = []

    func report(_ progress: TrainingWorkProgress) {
        reportedProgress.append(progress)
    }

    func records() -> [TrainingWorkProgress] {
        reportedProgress
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

private struct TestModelBundlePublicationValidator: ModelBundlePublicationValidating {
    func validatePublicationBundle(at bundleURL: URL) throws {
        let manifestURL = bundleURL.appendingPathComponent("manifest.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
    }
}

private final class FailingTemporaryPublicationValidator: ModelBundlePublicationValidating, Sendable {
    private let validationCount = Mutex(0)

    func validatePublicationBundle(at bundleURL: URL) throws {
        let manifestURL = bundleURL.appendingPathComponent("manifest.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let count = validationCount.withLock { count in
            count += 1
            return count
        }
        if count == 2 {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}

private final class FailingFinalPublicationValidator: ModelBundlePublicationValidating, Sendable {
    private let validationCount = Mutex(0)

    func validatePublicationBundle(at bundleURL: URL) throws {
        let manifestURL = bundleURL.appendingPathComponent("manifest.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let count = validationCount.withLock { count in
            count += 1
            return count
        }
        if count == 3 {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}

@MainActor
private final class FakeEvolutionBackend: EvolutionaryTrainingBackend {
    private(set) var seedRequests: [EvolutionSeedRequest] = []
    private(set) var nextGenerationRequests: [EvolutionGenerationRequest] = []

    /// Root the candidate checkpoints are written under.
    ///
    /// `EvolutionCandidateArtifactRetentionStore` resolves, protects and prunes
    /// checkpoints only inside `<artifactDirectory>/candidates`, and rejects any
    /// path outside it, so a backend that writes elsewhere fails every retention
    /// pass. Production wires `ManasMLXEvolutionBackend` to the same root.
    private let candidateRootDirectory: URL

    init(artifactDirectory: URL) {
        self.candidateRootDirectory = artifactDirectory
            .appendingPathComponent("candidates", isDirectory: true)
    }

    func seedPopulation(request: EvolutionSeedRequest) async throws -> EvolutionPopulation {
        seedRequests.append(request)
        return try population(
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
        return try population(
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
    ) throws -> EvolutionPopulation {
        let candidates = try (0..<config.populationSize).map { index in
            let isIncumbent = generationIndex == 0 && index == 0
            // Antithetic pairing mirrors the production convention: candidate 0
            // preserves the incumbent and carries no pair, and the remaining
            // candidates form +/- pairs by variation index.
            let variationIndex = index - 1
            let isAntithetic = config.antitheticSampling && variationIndex >= 0
            let checkpointID = "checkpoint-g\(generationIndex)-c\(index)"
            let checkpointURL = candidateRootDirectory
                .appendingPathComponent("generation-\(generationIndex)", isDirectory: true)
                .appendingPathComponent(checkpointID, isDirectory: true)
            try FileManager.default.createDirectory(at: checkpointURL, withIntermediateDirectories: true)
            try Data("checkpoint:\(checkpointID)".utf8).write(
                to: checkpointURL.appendingPathComponent("manifest.json"),
                options: [.atomic]
            )
            return GenomeCandidate(
                runID: config.runID,
                generationIndex: generationIndex,
                candidateID: "g\(generationIndex)-c\(index)",
                genomeID: "genome-g\(generationIndex)-c\(index)",
                parentCandidateIDs: parents,
                checkpointID: checkpointID,
                checkpointURL: checkpointURL,
                mutationRate: isIncumbent ? 0 : mutationRate,
                mutationNoiseScale: isIncumbent ? 0 : mutationNoiseScale,
                commonRandomSeed: commonRandomSeed,
                antitheticPairID: isAntithetic
                    ? "g\(generationIndex)-p\(variationIndex / 2)"
                    : nil,
                antitheticSign: isAntithetic
                    ? (variationIndex.isMultiple(of: 2) ? 1 : -1)
                    : nil,
                mutationSummary: isIncumbent ? "incumbent-parent" : (generationIndex == 0 ? "seeded" : "mutated"),
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

@MainActor
private final class FakeEvolutionEvaluator: EvolutionCandidateEvaluating {
    private(set) var requests: [EvolutionCandidateEvaluationRequest] = []
    let taskPassRate: Double
    let generationTaskPassRates: [Int: Double]
    let nonFiniteCandidateID: String?
    let unsafeCandidateID: String?
    let fixedFitness: Double?

    init(
        taskPassRate: Double = 1.0,
        generationTaskPassRates: [Int: Double] = [:],
        nonFiniteCandidateID: String? = nil,
        unsafeCandidateID: String? = nil,
        fixedFitness: Double? = nil
    ) {
        self.taskPassRate = taskPassRate
        self.generationTaskPassRates = generationTaskPassRates
        self.nonFiniteCandidateID = nonFiniteCandidateID
        self.unsafeCandidateID = unsafeCandidateID
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
            safetyViolationRate: request.candidate.candidateID == unsafeCandidateID ? 1 : 0,
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

@MainActor
private final class FakeEvolutionAcceptanceEvaluator: EvolutionCandidateAcceptanceEvaluating {
    enum EvidenceMode {
        case valid
        case pathTraversal
        case mutateCheckpoint
    }

    private(set) var requests: [EvolutionCandidateAcceptanceRequest] = []
    let taskPassRate: Double
    let returnedCandidateID: String?
    let evidenceMode: EvidenceMode
    let incumbentScalarFitness: Double

    init(
        taskPassRate: Double,
        returnedCandidateID: String? = nil,
        evidenceMode: EvidenceMode = .valid,
        incumbentScalarFitness: Double = 0
    ) {
        self.taskPassRate = taskPassRate
        self.returnedCandidateID = returnedCandidateID
        self.evidenceMode = evidenceMode
        self.incumbentScalarFitness = incumbentScalarFitness
    }

    func evaluateAcceptance(
        request: EvolutionCandidateAcceptanceRequest,
        progressReporter: (any TrainingProgressReporting)?
    ) async throws -> EvolutionCandidateAcceptanceResult {
        requests.append(request)
        if let progressReporter {
            try await progressReporter.report(TrainingWorkProgress(
                scope: TrainingWorkScope(
                    runID: request.config.runID,
                    generationIndex: request.candidate.generationIndex,
                    candidateID: request.candidate.candidateID
                ),
                phase: .candidateGate,
                state: .started,
                unit: TrainingWorkUnit(
                    kind: .candidate,
                    identifier: request.candidate.candidateID
                ),
                completedUnitCount: 0,
                totalUnitCount: 1,
                populationSize: 1
            ))
        }
        try FileManager.default.createDirectory(
            at: request.artifactDirectory,
            withIntermediateDirectories: true
        )
        let artifactURL = request.artifactDirectory.appendingPathComponent("fake-acceptance.json")
        let artifactData = Data("acceptance:\(request.candidate.candidateID)".utf8)
        try artifactData.write(to: artifactURL, options: [.atomic])
        let fitness = FitnessSummary(
            runID: request.config.runID,
            generationIndex: request.candidate.generationIndex,
            candidateID: returnedCandidateID ?? request.candidate.candidateID,
            taskID: request.config.taskID,
            scalarFitness: request.searchFitness.scalarFitness,
            rewardAverage: request.searchFitness.rewardAverage,
            taskPassRate: taskPassRate,
            safetyViolationRate: 0,
            holdTimeRatio: 1,
            energyPenalty: request.searchFitness.energyPenalty,
            noveltyScore: request.searchFitness.noveltyScore,
            workerThroughput: Double(request.workerCount),
            behaviorDescriptor: request.searchFitness.behaviorDescriptor
        )
        let incumbentFitness = FitnessSummary(
            runID: request.config.runID,
            generationIndex: request.incumbentCandidate.generationIndex,
            candidateID: request.incumbentCandidate.candidateID,
            taskID: request.config.taskID,
            scalarFitness: incumbentScalarFitness,
            rewardAverage: incumbentScalarFitness,
            taskPassRate: 1,
            safetyViolationRate: 0,
            holdTimeRatio: 1,
            energyPenalty: request.searchFitness.energyPenalty,
            workerThroughput: Double(request.workerCount)
        )
        let validEvidence = try EvolutionAcceptanceEvidenceIntegrity().reference(
            for: artifactURL,
            relativeTo: request.artifactDirectory,
            artifactType: "fake-acceptance-v1"
        )
        let evidence: [EvolutionCandidateAcceptanceEvidenceReference]
        switch evidenceMode {
        case .valid:
            evidence = [validEvidence]
        case .pathTraversal:
            evidence = [EvolutionCandidateAcceptanceEvidenceReference(
                artifactType: validEvidence.artifactType,
                relativePath: "../outside.json",
                sha256Digest: validEvidence.sha256Digest,
                byteCount: validEvidence.byteCount
            )]
        case .mutateCheckpoint:
            let checkpointURL = try #require(request.candidate.checkpointURL)
            try Data("mutated-during-acceptance".utf8).write(
                to: checkpointURL.appendingPathComponent("manifest.json"),
                options: [.atomic]
            )
            evidence = [validEvidence]
        }
        return EvolutionCandidateAcceptanceResult(
            fitness: fitness,
            incumbentFitness: incumbentFitness,
            evaluationContract: EvolutionCandidateAcceptanceEvaluationContract(
                evaluatorID: "FakeEvolutionAcceptanceEvaluator",
                scenarioSuiteIDs: ["test-suite"],
                episodesPerSuite: 1,
                determinismTier: "test",
                configurationDigest: EvolutionAcceptanceEvidenceIntegrity.sha256Digest(
                    of: Data("fake-acceptance-contract-v1".utf8)
                ),
                evaluationFidelity: .fullScenario,
                workPhase: .candidateGate,
                worldExecutionRequirement: .preferAcceleratorSharedWorld
            ),
            evidence: evidence
        )
    }
}

private func acceptanceEvolutionConfig(
    runID: String,
    generationCount: Int = 1
) -> EvolutionRunConfig {
    EvolutionRunConfig(
        runID: runID,
        taskID: "lift",
        configHash: "config-hash",
        policyID: "manasMLX",
        populationSize: 3,
        generationCount: generationCount,
        eliteCount: 1,
        workerCount: 1,
        mutationRate: 0.08
    )
}

private func strictEvolutionGatePolicy() -> EvolutionGatePolicy {
    EvolutionGatePolicy(
        eliteCount: 1,
        minimumTaskPassRate: 1,
        maximumSafetyViolationRate: 0,
        minimumHoldTimeRatio: 1
    )
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
