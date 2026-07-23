import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import Testing
import KuyuTraining

@Test func generatedArtifactCompatibilityVerifierRoundTripsRunArtifactsThroughFacade() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }

    let result = generatedArtifactRunResult(directory: directory)
    try TrainingArtifactWriter().write(
        manifest: result.manifest,
        metrics: result.metrics,
        convergence: result.convergence,
        checkpointDecision: result.checkpointDecision,
        scenarioRuns: try generatedArtifactScenarioRuns(runID: result.manifest.runID),
        to: directory
    )

    let report = try GeneratedTrainingArtifactCompatibilityVerifier().verify(
        GeneratedTrainingArtifactCompatibilityRequest(runArtifactDirectory: directory)
    )

    #expect(report.runArtifacts?.manifest.runID == result.manifest.runID)
    #expect(report.runArtifacts?.metrics.count == result.metrics.count)
    #expect(report.probeArtifacts == nil)
    #expect(report.checkpointEvaluationArtifact == nil)
}

@Test func generatedArtifactCompatibilityVerifierRoundTripsProbeArtifactsThroughFacade() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }

    let trainingDirectory = directory.appendingPathComponent("training", isDirectory: true)
    let training = generatedArtifactRunResult(directory: trainingDirectory)
    try TrainingArtifactWriter().write(
        manifest: training.manifest,
        metrics: training.metrics,
        convergence: training.convergence,
        checkpointDecision: training.checkpointDecision,
        scenarioRuns: try generatedArtifactScenarioRuns(runID: training.manifest.runID),
        to: trainingDirectory
    )

    let teacher = try generatedArtifactProbeSummary(stage: .teacherActiveAltitudeHold, passed: true)
    let initial = try generatedArtifactProbeSummary(stage: .initialPolicy, passed: false)
    let trained = try generatedArtifactProbeSummary(stage: .trainedPolicy, passed: true)
    let probeDecision = CheckpointDecision(
        runID: training.manifest.runID,
        state: .accepted,
        reason: "accepted",
        candidateCheckpointID: "candidate",
        candidateCheckpointURL: directory.appendingPathComponent("candidate"),
        publishedCheckpointURL: directory.appendingPathComponent("published"),
        decidedAt: Date(timeIntervalSince1970: 4)
    )
    let comparison = TrainingProbeComparison(
        probeID: "probe-public-artifact",
        trainingRunID: training.manifest.runID,
        teacher: teacher,
        initial: initial,
        trained: trained,
        training: training,
        minScoreDelta: 0,
        requireTeacherPass: true,
        requireTrainedPass: true
    ).selectingCheckpoint(from: probeDecision)
    let probeResult = TrainingProbeResult(
        manifest: TrainingProbeManifest(
            probeID: "probe-public-artifact",
            trainingRunID: training.manifest.runID,
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 5),
            terminalState: .completed
        ),
        teacher: teacher,
        initial: initial,
        training: training,
        trained: trained,
        comparison: comparison,
        probeCheckpointDecision: probeDecision
    )
    try TrainingProbeArtifactWriter().write(result: probeResult, to: directory)

    let report = try GeneratedTrainingArtifactCompatibilityVerifier().verify(
        GeneratedTrainingArtifactCompatibilityRequest(
            runArtifactDirectory: trainingDirectory,
            probeArtifactDirectory: directory
        )
    )

    #expect(report.runArtifacts?.manifest.runID == training.manifest.runID)
    #expect(report.probeArtifacts?.manifest.probeID == "probe-public-artifact")
    #expect(report.probeArtifacts?.training.manifest.runID == training.manifest.runID)
    #expect(report.probeArtifacts?.trained?.stage == .trainedPolicy)
}

@Test func generatedArtifactCompatibilityVerifierRejectsMismatchedRunAndProbeArtifacts() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }

    let probeDirectory = directory.appendingPathComponent("probe", isDirectory: true)
    let probeTrainingDirectory = probeDirectory.appendingPathComponent("training", isDirectory: true)
    let probeTraining = generatedArtifactRunResult(directory: probeTrainingDirectory)
    try TrainingArtifactWriter().write(
        manifest: probeTraining.manifest,
        metrics: probeTraining.metrics,
        convergence: probeTraining.convergence,
        checkpointDecision: probeTraining.checkpointDecision,
        scenarioRuns: try generatedArtifactScenarioRuns(runID: probeTraining.manifest.runID),
        to: probeTrainingDirectory
    )

    let teacher = try generatedArtifactProbeSummary(stage: .teacherActiveAltitudeHold, passed: true)
    let initial = try generatedArtifactProbeSummary(stage: .initialPolicy, passed: false)
    let trained = try generatedArtifactProbeSummary(stage: .trainedPolicy, passed: true)
    let probeDecision = CheckpointDecision(
        runID: probeTraining.manifest.runID,
        state: .accepted,
        reason: "accepted",
        candidateCheckpointID: "candidate",
        candidateCheckpointURL: directory.appendingPathComponent("candidate"),
        publishedCheckpointURL: directory.appendingPathComponent("published"),
        decidedAt: Date(timeIntervalSince1970: 4)
    )
    let comparison = TrainingProbeComparison(
        probeID: "probe-mismatched-public-artifact",
        trainingRunID: probeTraining.manifest.runID,
        teacher: teacher,
        initial: initial,
        trained: trained,
        training: probeTraining,
        minScoreDelta: 0,
        requireTeacherPass: true,
        requireTrainedPass: true
    ).selectingCheckpoint(from: probeDecision)
    try TrainingProbeArtifactWriter().write(
        result: TrainingProbeResult(
            manifest: TrainingProbeManifest(
                probeID: "probe-mismatched-public-artifact",
                trainingRunID: probeTraining.manifest.runID,
                startedAt: Date(timeIntervalSince1970: 1),
                completedAt: Date(timeIntervalSince1970: 5),
                terminalState: .completed
            ),
            teacher: teacher,
            initial: initial,
            training: probeTraining,
            trained: trained,
            comparison: comparison,
            probeCheckpointDecision: probeDecision
        ),
        to: probeDirectory
    )

    let runDirectory = directory.appendingPathComponent("standalone-run", isDirectory: true)
    let run = generatedArtifactRunResult(directory: runDirectory, runID: "standalone-public-artifact")
    try TrainingArtifactWriter().write(
        manifest: run.manifest,
        metrics: run.metrics,
        convergence: run.convergence,
        checkpointDecision: run.checkpointDecision,
        scenarioRuns: try generatedArtifactScenarioRuns(runID: run.manifest.runID),
        to: runDirectory
    )

    do {
        _ = try GeneratedTrainingArtifactCompatibilityVerifier().verify(
            GeneratedTrainingArtifactCompatibilityRequest(
                runArtifactDirectory: runDirectory,
                probeArtifactDirectory: probeDirectory
            )
        )
        Issue.record("Expected mismatched run/probe artifacts to fail closed.")
    } catch let error as GeneratedTrainingArtifactCompatibilityVerifier.VerificationError {
        switch error {
        case .incompatibleRunAndProbeArtifacts(let runID, let probeTrainingRunID):
            #expect(runID == run.manifest.runID)
            #expect(probeTrainingRunID == probeTraining.manifest.runID)
        default:
            Issue.record("Unexpected error: \(error)")
        }
    }
}

@Test func generatedArtifactCompatibilityVerifierRoundTripsCheckpointEvaluationThroughFacade() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }

    let profile = try TaskEvaluationProfile.profile(task: "attitude")
    let checkpointPath = directory.appendingPathComponent("checkpoint").path
    let artifact = CheckpointEvaluationArtifact(
        evaluationID: "checkpoint-public-artifact",
        startedAt: Date(timeIntervalSince1970: 1),
        task: profile.task,
        profileID: profile.profileID,
        checkpointPath: checkpointPath,
        teacherScore: 1,
        policyScore: 1,
        teacherPassed: true,
        policyPassed: true,
        failureReasons: [],
        expectedQualityKeys: [],
        qualitySummary: [],
        motorMAE: nil,
        driveMAE: nil,
        finalAltitudeDelta: nil,
        policyAverageMotorFinalOutputByIndex: nil,
        teacherAverageMotorFinalOutputByIndex: nil,
        diagnostics: nil
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try encoder.encode(artifact).write(
        to: directory.appendingPathComponent(CheckpointEvaluationArtifact.fileName),
        options: [.atomic]
    )

    let report = try GeneratedTrainingArtifactCompatibilityVerifier().verify(
        GeneratedTrainingArtifactCompatibilityRequest(
            checkpointEvaluation: CheckpointEvaluationArtifactCompatibilityRequest(
                artifactDirectory: directory,
                expectedProfile: profile,
                expectedCheckpointPath: checkpointPath,
                requiresPolicyPass: true
            )
        )
    )

    #expect(report.checkpointEvaluationArtifact?.evaluationID == artifact.evaluationID)
    #expect(report.checkpointEvaluationArtifact?.profileID == profile.profileID)
}

@Test func generatedArtifactCompatibilityVerifierRoundTripsEvolutionArtifactsThroughFacade() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }

    try generatedEvolutionArtifact(directory: directory)

    let report = try GeneratedTrainingArtifactCompatibilityVerifier().verify(
        GeneratedTrainingArtifactCompatibilityRequest(evolutionArtifactDirectory: directory)
    )

    #expect(report.runArtifacts == nil)
    #expect(report.probeArtifacts == nil)
    #expect(report.evolutionArtifacts?.manifest.runID == "evolution-public-artifact")
    #expect(report.evolutionArtifacts?.acceptedCheckpoint.accepted == true)
}

@Test func evolutionArtifactValidatorRejectsEliteFitnessThatDiffersFromCandidateEvaluation() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }
    try generatedEvolutionArtifact(directory: directory)
    let invalidArchive = EvolutionEliteArchive(
        runID: "evolution-public-artifact",
        eliteCandidateIDs: ["candidate-0"],
        bestCandidateID: "candidate-0",
        bestFitness: 2
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(invalidArchive).write(
        to: directory.appendingPathComponent("elite-archive.json"),
        options: [.atomic]
    )

    #expect(throws: EvolutionRunArtifactValidator.ValidationError.bestFitnessMismatch(
        candidateID: "candidate-0",
        archived: 2,
        evaluated: 1
    )) {
        _ = try EvolutionRunArtifactValidator().validatedBundle(in: directory)
    }
}

@Test func generatedArtifactCompatibilityVerifierRoundTripsProjectEvidencePackThroughFacade() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }
    try generatedArtifactCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    _ = try TrainingProjectEvidencePackArtifactStore().writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [generatedArtifactDatasetMetadata()],
        curriculum: generatedArtifactCurriculum(),
        checkpointDecision: generatedArtifactCheckpointDecision(),
        regressionArtifacts: [generatedArtifactRegressionReference()],
        to: directory,
        createdAt: Date(timeIntervalSince1970: 10)
    )

    let report = try GeneratedTrainingArtifactCompatibilityVerifier().verify(
        GeneratedTrainingArtifactCompatibilityRequest(projectEvidencePackDirectory: directory)
    )

    #expect(report.projectEvidencePack?.projectID == "reference-foundation")
    #expect(report.projectEvidencePack?.datasets.map(\.datasetID) == ["episode-public-artifact"])
    #expect(report.runArtifacts == nil)
    #expect(report.evolutionArtifacts == nil)
}

@Test func generatedArtifactCompatibilityVerifierRoundTripsProjectEvidencePackWithPhysicsCorpusEvidence() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }
    try generatedArtifactCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let summary = generatedArtifactDescriptorCorpusSummary()
    let physicsPath = "physics/descriptor-corpus-acceptance.json"
    try generatedArtifactWriteJSON(summary, to: directory.appendingPathComponent(physicsPath))
    let physicsEvidence = TrainingProjectEvidencePack.PhysicsCorpusEvidence(
        summary: summary,
        path: physicsPath
    )
    _ = try TrainingProjectEvidencePackArtifactStore().writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [generatedArtifactDatasetMetadata()],
        curriculum: generatedArtifactCurriculum(),
        checkpointDecision: generatedArtifactCheckpointDecision(),
        regressionArtifacts: [generatedArtifactRegressionReference()],
        stressSuites: [],
        physicsCorpora: [physicsEvidence],
        to: directory,
        createdAt: Date(timeIntervalSince1970: 10)
    )

    let report = try GeneratedTrainingArtifactCompatibilityVerifier().verify(
        GeneratedTrainingArtifactCompatibilityRequest(projectEvidencePackDirectory: directory)
    )

    #expect(report.projectEvidencePack?.physicsCorpora == [physicsEvidence])
    #expect(report.projectEvidencePack?.physicsCorpora.first?.acceptedRecordCount == 1)
}

@Test func generatedArtifactCompatibilityVerifierRoundTripsObservabilityArtifactThroughFacade() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }
    let artifact = generatedArtifactObservabilityArtifact()
    let artifactURL = directory.appendingPathComponent(ConsciousUnconsciousObservabilityArtifact.fileName)
    _ = try ConsciousUnconsciousObservabilityArtifactStore().write(artifact, to: artifactURL)

    let report = try GeneratedTrainingArtifactCompatibilityVerifier().verify(
        GeneratedTrainingArtifactCompatibilityRequest(observabilityArtifactURL: artifactURL)
    )

    #expect(report.observabilityArtifact?.runID == "run-public-artifact")
    #expect(report.observabilityArtifact?.upwardSummaries.first?.channels.count == 5)
    #expect(report.projectEvidencePack == nil)
}

@Test func generatedArtifactCompatibilityVerifierRoundTripsSummaryOutcomeThroughFacade() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }
    let summary = TrainingRunSummary(
        runID: TrainingRunID("summary-outcome-public-artifact"),
        artifactRoot: directory,
        terminalState: .completed,
        generationCount: 2,
        candidateCount: 8
    )
    _ = try TrainingRunSummaryOutcomeArtifactStore().write(
        summary: summary,
        completedAt: Date(timeIntervalSince1970: 12),
        to: directory
    )

    let report = try GeneratedTrainingArtifactCompatibilityVerifier().verify(
        GeneratedTrainingArtifactCompatibilityRequest(summaryOutcomeDirectory: directory)
    )

    #expect(report.summaryOutcomeArtifact?.summary == summary)
    #expect(report.summaryOutcomeArtifact?.completedAt == Date(timeIntervalSince1970: 12))
    #expect(report.runArtifacts == nil)
    #expect(report.projectEvidencePack == nil)
}

@Test func generatedArtifactCompatibilityVerifierRejectsNonTerminalSummaryOutcome() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }
    let artifact = TrainingRunSummaryOutcomeArtifact(
        completedAt: Date(timeIntervalSince1970: 13),
        summary: TrainingRunSummary(
            runID: TrainingRunID("summary-outcome-non-terminal"),
            artifactRoot: directory,
            terminalState: .running
        )
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let artifactURL = directory.appendingPathComponent(
        TrainingRunSummaryOutcomeArtifact.fileName
    )
    try encoder.encode(artifact).write(
        to: artifactURL,
        options: [.atomic]
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: artifactURL.path
    )

    do {
        _ = try GeneratedTrainingArtifactCompatibilityVerifier().verify(
            GeneratedTrainingArtifactCompatibilityRequest(summaryOutcomeDirectory: directory)
        )
        Issue.record("Expected non-terminal summary outcome artifact to fail closed.")
    } catch GeneratedTrainingArtifactCompatibilityVerifier.VerificationError
        .invalidSummaryOutcomeArtifact(.invalidArtifact(.nonTerminalState(.running))) {
    }
}

@Test func generatedArtifactCompatibilityVerifierComparesProjectEvidencePacksThroughFacade() throws {
    let incumbentDirectory = try generatedArtifactTemporaryDirectory()
    let candidateDirectory = try generatedArtifactTemporaryDirectory()
    defer {
        generatedArtifactCleanup(incumbentDirectory)
        generatedArtifactCleanup(candidateDirectory)
    }
    try generatedArtifactCreateFile(
        at: incumbentDirectory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    try generatedArtifactCreateFile(
        at: candidateDirectory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let store = TrainingProjectEvidencePackArtifactStore()
    _ = try store.writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [generatedArtifactDatasetMetadata()],
        curriculum: generatedArtifactCurriculum(),
        checkpointDecision: generatedArtifactCheckpointDecision(
            state: .staged,
            decidedAt: Date(timeIntervalSince1970: 10)
        ),
        regressionArtifacts: [generatedArtifactRegressionReference()],
        to: incumbentDirectory,
        createdAt: Date(timeIntervalSince1970: 10)
    )
    _ = try store.writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [generatedArtifactDatasetMetadata()],
        curriculum: generatedArtifactCurriculum(),
        checkpointDecision: generatedArtifactCheckpointDecision(
            state: .accepted,
            decidedAt: Date(timeIntervalSince1970: 20)
        ),
        regressionArtifacts: [generatedArtifactRegressionReference()],
        to: candidateDirectory,
        createdAt: Date(timeIntervalSince1970: 20)
    )

    let comparison = try GeneratedTrainingArtifactCompatibilityVerifier()
        .requirePreferredProjectEvidenceCandidate(
            incumbentDirectory: incumbentDirectory,
            candidateDirectory: candidateDirectory
        )

    #expect(comparison.decision == .preferCandidate)
    #expect(comparison.dominantFactor == .checkpointState)
    #expect(comparison.incumbentScore.checkpointState == .staged)
    #expect(comparison.candidateScore.checkpointState == .accepted)
}

@Test func generatedArtifactCompatibilityVerifierPrefersHardwareBackedProjectEvidenceCandidate() throws {
    let incumbentDirectory = try generatedArtifactTemporaryDirectory()
    let candidateDirectory = try generatedArtifactTemporaryDirectory()
    defer {
        generatedArtifactCleanup(incumbentDirectory)
        generatedArtifactCleanup(candidateDirectory)
    }
    try generatedArtifactCreateFile(
        at: incumbentDirectory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    try generatedArtifactCreateFile(
        at: candidateDirectory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )

    let physicsPath = "physics/descriptor-corpus-acceptance.json"
    let incumbentSummary = generatedArtifactDescriptorCorpusSummary()
    let candidateSummary = generatedArtifactDescriptorCorpusSummary(
        requiredReadiness: .hardwareParity,
        hardwareParity: .accepted,
        hardwareEvidence: generatedArtifactHardwareEvidence(reportHash: "hardware-report-hash-a")
    )
    try generatedArtifactWriteJSON(incumbentSummary, to: incumbentDirectory.appendingPathComponent(physicsPath))
    try generatedArtifactWriteJSON(candidateSummary, to: candidateDirectory.appendingPathComponent(physicsPath))

    let store = TrainingProjectEvidencePackArtifactStore()
    _ = try store.writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [generatedArtifactDatasetMetadata()],
        curriculum: generatedArtifactCurriculum(),
        checkpointDecision: generatedArtifactCheckpointDecision(decidedAt: Date(timeIntervalSince1970: 20)),
        regressionArtifacts: [generatedArtifactRegressionReference()],
        physicsCorpora: [
            TrainingProjectEvidencePack.PhysicsCorpusEvidence(summary: incumbentSummary, path: physicsPath),
        ],
        to: incumbentDirectory,
        createdAt: Date(timeIntervalSince1970: 20)
    )
    _ = try store.writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [generatedArtifactDatasetMetadata()],
        curriculum: generatedArtifactCurriculum(),
        checkpointDecision: generatedArtifactCheckpointDecision(decidedAt: Date(timeIntervalSince1970: 10)),
        regressionArtifacts: [generatedArtifactRegressionReference()],
        physicsCorpora: [
            TrainingProjectEvidencePack.PhysicsCorpusEvidence(summary: candidateSummary, path: physicsPath),
        ],
        to: candidateDirectory,
        createdAt: Date(timeIntervalSince1970: 10)
    )

    let comparison = try GeneratedTrainingArtifactCompatibilityVerifier()
        .requirePreferredProjectEvidenceCandidate(
            incumbentDirectory: incumbentDirectory,
            candidateDirectory: candidateDirectory
        )

    #expect(comparison.decision == .preferCandidate)
    #expect(comparison.dominantFactor == .physicsCorpusAcceptedHardwareParity)
    #expect(comparison.incumbentScore.physicsCorpusAcceptedRecordCount == 1)
    #expect(comparison.candidateScore.physicsCorpusAcceptedRecordCount == 1)
    #expect(comparison.candidateScore.physicsCorpusAcceptedHardwareParityRecordCount == 1)
    #expect(comparison.candidateScore.physicsCorpusHardwareEvidenceRecordCount == 1)
    #expect(comparison.candidateScore.physicsCorpusHardwareReportHashCount == 1)
}

@Test func generatedArtifactCompatibilityVerifierPrefersContactTrainingProjectEvidenceCandidate() throws {
    let incumbentDirectory = try generatedArtifactTemporaryDirectory()
    let candidateDirectory = try generatedArtifactTemporaryDirectory()
    defer {
        generatedArtifactCleanup(incumbentDirectory)
        generatedArtifactCleanup(candidateDirectory)
    }
    try generatedArtifactCreateFile(
        at: incumbentDirectory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    try generatedArtifactCreateFile(
        at: candidateDirectory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )

    let physicsPath = "physics/descriptor-corpus-acceptance.json"
    let incumbentSummary = generatedArtifactDescriptorCorpusSummary()
    let candidateSummary = generatedArtifactDescriptorCorpusSummary(
        requiredReadiness: .contactTraining,
        contactReplay: generatedArtifactContactReplayEvidence()
    )
    try generatedArtifactWriteJSON(incumbentSummary, to: incumbentDirectory.appendingPathComponent(physicsPath))
    try generatedArtifactWriteJSON(candidateSummary, to: candidateDirectory.appendingPathComponent(physicsPath))

    let store = TrainingProjectEvidencePackArtifactStore()
    _ = try store.writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [generatedArtifactDatasetMetadata()],
        curriculum: generatedArtifactCurriculum(),
        checkpointDecision: generatedArtifactCheckpointDecision(decidedAt: Date(timeIntervalSince1970: 20)),
        regressionArtifacts: [generatedArtifactRegressionReference()],
        physicsCorpora: [
            TrainingProjectEvidencePack.PhysicsCorpusEvidence(summary: incumbentSummary, path: physicsPath),
        ],
        to: incumbentDirectory,
        createdAt: Date(timeIntervalSince1970: 20)
    )
    _ = try store.writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [generatedArtifactDatasetMetadata()],
        curriculum: generatedArtifactCurriculum(),
        checkpointDecision: generatedArtifactCheckpointDecision(decidedAt: Date(timeIntervalSince1970: 10)),
        regressionArtifacts: [generatedArtifactRegressionReference()],
        physicsCorpora: [
            TrainingProjectEvidencePack.PhysicsCorpusEvidence(summary: candidateSummary, path: physicsPath),
        ],
        to: candidateDirectory,
        createdAt: Date(timeIntervalSince1970: 10)
    )

    let comparison = try GeneratedTrainingArtifactCompatibilityVerifier()
        .requirePreferredProjectEvidenceCandidate(
            incumbentDirectory: incumbentDirectory,
            candidateDirectory: candidateDirectory
        )

    #expect(comparison.decision == .preferCandidate)
    #expect(comparison.dominantFactor == .physicsCorpusContactReplay)
    #expect(comparison.incumbentScore.physicsCorpusAcceptedRecordCount == 1)
    #expect(comparison.candidateScore.physicsCorpusAcceptedRecordCount == 1)
    #expect(comparison.incumbentScore.physicsCorpusContactReplayRecordCount == 0)
    #expect(comparison.candidateScore.physicsCorpusContactReplayRecordCount == 1)
}

@Test func generatedArtifactCompatibilityVerifierRejectsContactTrainingCandidateBelowHardwareParity() throws {
    let incumbentDirectory = try generatedArtifactTemporaryDirectory()
    let candidateDirectory = try generatedArtifactTemporaryDirectory()
    defer {
        generatedArtifactCleanup(incumbentDirectory)
        generatedArtifactCleanup(candidateDirectory)
    }
    try generatedArtifactCreateFile(
        at: incumbentDirectory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    try generatedArtifactCreateFile(
        at: candidateDirectory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )

    let physicsPath = "physics/descriptor-corpus-acceptance.json"
    let incumbentSummary = generatedArtifactDescriptorCorpusSummary(
        requiredReadiness: .hardwareParity,
        hardwareParity: .accepted,
        hardwareEvidence: generatedArtifactHardwareEvidence(reportHash: "hardware-report-hash-a")
    )
    let candidateSummary = generatedArtifactDescriptorCorpusSummary(
        requiredReadiness: .contactTraining,
        contactReplay: generatedArtifactContactReplayEvidence()
    )
    try generatedArtifactWriteJSON(incumbentSummary, to: incumbentDirectory.appendingPathComponent(physicsPath))
    try generatedArtifactWriteJSON(candidateSummary, to: candidateDirectory.appendingPathComponent(physicsPath))

    let store = TrainingProjectEvidencePackArtifactStore()
    _ = try store.writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [generatedArtifactDatasetMetadata()],
        curriculum: generatedArtifactCurriculum(),
        checkpointDecision: generatedArtifactCheckpointDecision(decidedAt: Date(timeIntervalSince1970: 10)),
        regressionArtifacts: [generatedArtifactRegressionReference()],
        physicsCorpora: [
            TrainingProjectEvidencePack.PhysicsCorpusEvidence(summary: incumbentSummary, path: physicsPath),
        ],
        to: incumbentDirectory,
        createdAt: Date(timeIntervalSince1970: 10)
    )
    _ = try store.writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [generatedArtifactDatasetMetadata()],
        curriculum: generatedArtifactCurriculum(),
        checkpointDecision: generatedArtifactCheckpointDecision(decidedAt: Date(timeIntervalSince1970: 20)),
        regressionArtifacts: [generatedArtifactRegressionReference()],
        physicsCorpora: [
            TrainingProjectEvidencePack.PhysicsCorpusEvidence(summary: candidateSummary, path: physicsPath),
        ],
        to: candidateDirectory,
        createdAt: Date(timeIntervalSince1970: 20)
    )

    let verifier = GeneratedTrainingArtifactCompatibilityVerifier()
    let comparison = try verifier.compareProjectEvidencePacks(
        incumbentDirectory: incumbentDirectory,
        candidateDirectory: candidateDirectory
    )
    #expect(comparison.decision == .keepIncumbent)
    #expect(comparison.dominantFactor == .physicsCorpusAcceptedHardwareParity)
    #expect(comparison.candidateScore.physicsCorpusContactReplayRecordCount == 1)

    do {
        try verifier.requirePreferredProjectEvidenceCandidate(comparison)
        Issue.record("Expected contact-training evidence to stay below hardware-parity evidence.")
    } catch GeneratedTrainingArtifactCompatibilityVerifier.VerificationError
        .projectEvidenceCandidateNotPreferred(let rejectedComparison) {
        #expect(rejectedComparison == comparison)
    }
}

@Test func generatedArtifactCompatibilityVerifierRejectsNonPreferredProjectEvidenceCandidate() throws {
    let incumbentDirectory = try generatedArtifactTemporaryDirectory()
    let candidateDirectory = try generatedArtifactTemporaryDirectory()
    defer {
        generatedArtifactCleanup(incumbentDirectory)
        generatedArtifactCleanup(candidateDirectory)
    }
    try generatedArtifactCreateFile(
        at: incumbentDirectory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    try generatedArtifactCreateFile(
        at: candidateDirectory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let store = TrainingProjectEvidencePackArtifactStore()
    _ = try store.writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [generatedArtifactDatasetMetadata()],
        curriculum: generatedArtifactCurriculum(),
        checkpointDecision: generatedArtifactCheckpointDecision(
            state: .accepted,
            decidedAt: Date(timeIntervalSince1970: 20)
        ),
        regressionArtifacts: [generatedArtifactRegressionReference()],
        to: incumbentDirectory,
        createdAt: Date(timeIntervalSince1970: 20)
    )
    _ = try store.writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [generatedArtifactDatasetMetadata()],
        curriculum: generatedArtifactCurriculum(),
        checkpointDecision: generatedArtifactCheckpointDecision(
            state: .staged,
            decidedAt: Date(timeIntervalSince1970: 10)
        ),
        regressionArtifacts: [generatedArtifactRegressionReference()],
        to: candidateDirectory,
        createdAt: Date(timeIntervalSince1970: 10)
    )

    let verifier = GeneratedTrainingArtifactCompatibilityVerifier()
    let comparison = try verifier.compareProjectEvidencePacks(
        incumbentDirectory: incumbentDirectory,
        candidateDirectory: candidateDirectory
    )
    #expect(comparison.decision == .keepIncumbent)

    do {
        try verifier.requirePreferredProjectEvidenceCandidate(comparison)
        Issue.record("Expected non-preferred project evidence candidate to fail through the public verifier gate.")
    } catch GeneratedTrainingArtifactCompatibilityVerifier.VerificationError
        .projectEvidenceCandidateNotPreferred(let rejectedComparison) {
        #expect(rejectedComparison == comparison)
    }
}

@Test func generatedArtifactCompatibilityVerifierValidatesProjectEvidenceDatasetCuration() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }
    try generatedArtifactCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    _ = try TrainingProjectEvidencePackArtifactStore().writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [generatedArtifactDatasetMetadata()],
        curriculum: generatedArtifactCurriculum(),
        checkpointDecision: generatedArtifactCheckpointDecision(),
        regressionArtifacts: [generatedArtifactRegressionReference()],
        to: directory,
        createdAt: Date(timeIntervalSince1970: 10)
    )
    let policy = TrainingDatasetCurationPolicy(
        policyID: "reference-foundation-curation",
        minimumDatasetCount: 1,
        minimumTotalRecordCount: 16,
        minimumRecordCountPerDataset: 16,
        requiredScenarioIDs: ["scenario-public-artifact"],
        requiresRewardDescriptor: true,
        requiresProvenance: true
    )

    let report = try GeneratedTrainingArtifactCompatibilityVerifier()
        .validateProjectEvidenceDatasetCuration(from: directory, policy: policy)

    #expect(report.accepted)
    #expect(report.datasetIDs == ["episode-public-artifact"])
    #expect(report.totalRecordCount == 16)
}

@Test func generatedArtifactCompatibilityVerifierRejectsProjectEvidenceDatasetCurationFailure() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }
    try generatedArtifactCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    _ = try TrainingProjectEvidencePackArtifactStore().writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [generatedArtifactDatasetMetadata()],
        curriculum: generatedArtifactCurriculum(),
        checkpointDecision: generatedArtifactCheckpointDecision(),
        regressionArtifacts: [generatedArtifactRegressionReference()],
        to: directory,
        createdAt: Date(timeIntervalSince1970: 10)
    )
    let policy = TrainingDatasetCurationPolicy(
        policyID: "reference-foundation-curation",
        requiredScenarioIDs: ["missing-scenario"]
    )

    #expect(throws: GeneratedTrainingArtifactCompatibilityVerifier.VerificationError
        .projectEvidenceDatasetCurationRejected(.missingRequiredScenarioID("missing-scenario"))) {
        _ = try GeneratedTrainingArtifactCompatibilityVerifier()
            .validateProjectEvidenceDatasetCuration(from: directory, policy: policy)
    }
}

@Test func generatedArtifactCompatibilityVerifierRejectsInvalidProjectEvidencePack() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }
    let pack = try TrainingProjectEvidencePackValidator().makePack(
        projectID: "reference-foundation",
        datasetMetadata: [generatedArtifactDatasetMetadata()],
        curriculum: generatedArtifactCurriculum(),
        checkpointDecision: generatedArtifactCheckpointDecision(),
        regressionArtifacts: [generatedArtifactRegressionReference()],
        createdAt: Date(timeIntervalSince1970: 10)
    )
    _ = try TrainingProjectEvidencePackArtifactStore().write(
        pack,
        to: directory,
        requireRegressionArtifactsExist: false
    )

    do {
        _ = try GeneratedTrainingArtifactCompatibilityVerifier().verify(
            GeneratedTrainingArtifactCompatibilityRequest(projectEvidencePackDirectory: directory)
        )
        Issue.record("Expected invalid project evidence pack to fail through the public verifier error.")
    } catch GeneratedTrainingArtifactCompatibilityVerifier.VerificationError
        .invalidProjectEvidencePack(.missingReferencedRegressionArtifact(let path)) {
        #expect(path == "evaluations/final/checkpoint-evaluation.json")
    }
}

@Test func generatedArtifactCompatibilityVerifierProjectsEvolutionPublicationStatus() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }

    try generatedEvolutionArtifact(directory: directory)

    let verifier = GeneratedTrainingArtifactCompatibilityVerifier()
    let artifacts = try verifier.validatedEvolutionArtifacts(in: directory)
    let projection = verifier.evolutionPublicationProjection(for: artifacts)

    #expect(projection.accepted)
    #expect(projection.acceptedCheckpointPath == directory.appendingPathComponent("checkpoint-0").path)
    #expect(projection.acceptedCandidateID == "candidate-0")
    #expect(projection.bestCheckpointPath == directory.appendingPathComponent("checkpoint-0").path)
    #expect(projection.bestCandidateID == "candidate-0")
    #expect(projection.reasons.isEmpty)
    #expect(projection.decisionPath == directory.appendingPathComponent(EvolutionAcceptedCheckpointDecision.fileName).path)
    try verifier.requireAcceptedEvolutionCheckpoint(projection)
}

@Test func generatedArtifactCompatibilityVerifierRejectsUnacceptedEvolutionPublication() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }

    try generatedEvolutionArtifact(directory: directory, terminalState: .rejected, accepted: false)

    let verifier = GeneratedTrainingArtifactCompatibilityVerifier()
    let projection = try verifier.validatedEvolutionPublicationProjection(in: directory)

    #expect(!projection.accepted)
    #expect(projection.acceptedCheckpointPath == nil)
    do {
        try verifier.requireAcceptedEvolutionCheckpoint(projection)
        Issue.record("Expected rejected evolution publication to fail closed.")
    } catch GeneratedTrainingArtifactCompatibilityVerifier.VerificationError.evolutionCheckpointNotAccepted(let reasons) {
        #expect(reasons.contains("not-accepted"))
    }
}

@Test func generatedArtifactCompatibilityVerifierRejectsMissingEvolutionArtifacts() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }

    do {
        _ = try GeneratedTrainingArtifactCompatibilityVerifier().verify(
            GeneratedTrainingArtifactCompatibilityRequest(evolutionArtifactDirectory: directory)
        )
        Issue.record("Expected missing evolution artifact to fail closed.")
    } catch GeneratedTrainingArtifactCompatibilityVerifier.VerificationError.missingEvolutionArtifact(let fileName) {
        #expect(fileName == EvolutionRunArtifactContract.fileName)
    }
}

@Test func generatedArtifactCompatibilityVerifierRejectsMissingCheckpointEvaluationArtifact() throws {
    let directory = try generatedArtifactTemporaryDirectory()
    defer { generatedArtifactCleanup(directory) }

    let profile = try TaskEvaluationProfile.profile(task: "attitude")

    do {
        _ = try GeneratedTrainingArtifactCompatibilityVerifier().validatedCheckpointEvaluationArtifact(
            CheckpointEvaluationArtifactCompatibilityRequest(
                artifactDirectory: directory,
                expectedProfile: profile,
                expectedCheckpointPath: directory.appendingPathComponent("checkpoint").path,
                requiresPolicyPass: true
            )
        )
        Issue.record("Expected missing checkpoint evaluation artifact to fail closed.")
    } catch GeneratedTrainingArtifactCompatibilityVerifier.VerificationError.missingCheckpointEvaluationArtifact(let fileName) {
        #expect(fileName == CheckpointEvaluationArtifact.fileName)
    }
}

@Test func generatedArtifactCompatibilityVerifierValidatesLoadedCheckpointEvaluationArtifact() throws {
    let profile = try TaskEvaluationProfile.profile(task: "attitude")
    let artifact = CheckpointEvaluationArtifact(
        evaluationID: "loaded-checkpoint-public-artifact",
        startedAt: Date(timeIntervalSince1970: 1),
        task: profile.task,
        profileID: profile.profileID,
        checkpointPath: "/tmp/loaded-checkpoint",
        teacherScore: 1,
        policyScore: 1,
        teacherPassed: true,
        policyPassed: true,
        failureReasons: [],
        expectedQualityKeys: [],
        qualitySummary: [],
        motorMAE: nil,
        driveMAE: nil,
        finalAltitudeDelta: nil,
        policyAverageMotorFinalOutputByIndex: nil,
        teacherAverageMotorFinalOutputByIndex: nil,
        diagnostics: nil
    )

    try GeneratedTrainingArtifactCompatibilityVerifier().validateCheckpointEvaluationArtifact(
        artifact,
        expectedProfile: profile,
        expectedCheckpointPath: "/tmp/loaded-checkpoint",
        requiresPolicyPass: true
    )
}

@Test func generatedArtifactCompatibilityVerifierWrapsCheckpointEvaluationValidationErrors() throws {
    let profile = try TaskEvaluationProfile.profile(task: "attitude")
    let artifact = CheckpointEvaluationArtifact(
        evaluationID: "invalid-checkpoint-public-artifact",
        startedAt: Date(timeIntervalSince1970: 1),
        task: profile.task,
        profileID: profile.profileID,
        checkpointPath: "/tmp/wrong-checkpoint",
        teacherScore: 1,
        policyScore: 1,
        teacherPassed: true,
        policyPassed: true,
        failureReasons: [],
        expectedQualityKeys: [],
        qualitySummary: [],
        motorMAE: nil,
        driveMAE: nil,
        finalAltitudeDelta: nil,
        policyAverageMotorFinalOutputByIndex: nil,
        teacherAverageMotorFinalOutputByIndex: nil,
        diagnostics: nil
    )

    do {
        try GeneratedTrainingArtifactCompatibilityVerifier().validateCheckpointEvaluationArtifact(
            artifact,
            expectedProfile: profile,
            expectedCheckpointPath: "/tmp/expected-checkpoint",
            requiresPolicyPass: true
        )
        Issue.record("Expected checkpoint evaluation validation error to fail through the public verifier error.")
    } catch GeneratedTrainingArtifactCompatibilityVerifier.VerificationError
        .invalidCheckpointEvaluationArtifact(.checkpointMismatch(let expected, let actual)) {
        #expect(expected == "/tmp/expected-checkpoint")
        #expect(actual == "/tmp/wrong-checkpoint")
    }
}

@Test func generatedArtifactCompatibilityVerifierRejectsEmptyRequest() throws {
    do {
        _ = try GeneratedTrainingArtifactCompatibilityVerifier().verify(
            GeneratedTrainingArtifactCompatibilityRequest()
        )
        Issue.record("Expected empty generated artifact verification request to fail closed.")
    } catch GeneratedTrainingArtifactCompatibilityVerifier.VerificationError.emptyRequest {
    }
}

private func generatedArtifactRunResult(
    directory: URL,
    runID: String = "run-public-artifact"
) -> TrainingRunResult {
    let manifest = LearningRunManifest(
        runID: runID,
        mode: .supervised,
        configHash: "config-hash",
        suiteID: "attitude",
        seedSet: [1],
        policyID: "policy",
        outputCheckpointID: "candidate",
        workerCount: 1,
        startedAt: Date(timeIntervalSince1970: 1),
        completedAt: Date(timeIntervalSince1970: 2),
        terminalState: .completed
    )
    let metrics = [
        TrainingMetricRecord(runID: manifest.runID, iteration: 1, kind: .score, value: 1),
        TrainingMetricRecord(runID: manifest.runID, iteration: 1, kind: .loss, value: 0.1),
    ]
    let convergence = ConvergenceSummary(
        runID: manifest.runID,
        accepted: true,
        reason: "accepted",
        bestCheckpointID: "candidate",
        finalTrainingLoss: 0.1,
        finalValidationLoss: nil,
        rewardMovingAverage: nil,
        passRate: 1,
        failureRate: 0,
        safetyRegressionDetected: false,
        plateauDetected: false,
        overfitRiskDetected: false
    )
    let checkpointDecision = CheckpointDecision(
        runID: manifest.runID,
        state: .accepted,
        reason: "accepted",
        candidateCheckpointID: "candidate",
        candidateCheckpointURL: directory.appendingPathComponent("candidate"),
        publishedCheckpointURL: directory.appendingPathComponent("published"),
        decidedAt: Date(timeIntervalSince1970: 3)
    )
    return TrainingRunResult(
        manifest: manifest,
        metrics: metrics,
        convergence: convergence,
        checkpointDecision: checkpointDecision
    )
}

private func generatedEvolutionArtifact(
    directory: URL,
    terminalState: EvolutionRunTerminalState = .completed,
    accepted: Bool = true
) throws {
    let runID = "evolution-public-artifact"
    let candidateID = "candidate-0"
    let checkpointURL = directory.appendingPathComponent("checkpoint-0", isDirectory: true)
    try generatedArtifactCreateFile(
        at: checkpointURL.appendingPathComponent("checkpoint.json", isDirectory: false)
    )
    let manifest = EvolutionRunManifest(
        runID: runID,
        taskID: "lift",
        configHash: "config-hash",
        policyID: "manasMLX",
        populationSize: 1,
        generationCount: 1,
        eliteCount: 1,
        workerCount: 1,
        candidateAcceptanceMode: .dedicatedEvaluation,
        startedAt: Date(timeIntervalSince1970: 1),
        completedAt: Date(timeIntervalSince1970: 2),
        terminalState: terminalState
    )
    let generation = PopulationGenerationRecord(
        runID: runID,
        generationIndex: 0,
        candidateCount: 1,
        evaluatedCandidateCount: 1,
        eliteCandidateIDs: [candidateID],
        bestCandidateID: candidateID,
        bestFitness: 1,
        accepted: accepted,
        rejectionReasons: accepted ? [] : ["not-accepted"],
        createdAt: Date(timeIntervalSince1970: 2)
    )
    let candidate = GenomeCandidate(
        runID: runID,
        generationIndex: 0,
        candidateID: candidateID,
        genomeID: "genome-0",
        checkpointID: "checkpoint-0",
        checkpointURL: checkpointURL,
        mutationRate: 0,
        mutationNoiseScale: 0,
        isIncumbent: true
    )
    let fitness = FitnessSummary(
        runID: runID,
        generationIndex: 0,
        candidateID: candidateID,
        taskID: "lift",
        scalarFitness: 1,
        rewardAverage: 1,
        taskPassRate: 1,
        safetyViolationRate: 0,
        holdTimeRatio: 1,
        altitudeErrorRatio: 0,
        behaviorDescriptor: ["taskPassRate": 1]
    )
    let acceptanceDirectory = directory.appendingPathComponent("acceptance", isDirectory: true)
    try FileManager.default.createDirectory(
        at: acceptanceDirectory,
        withIntermediateDirectories: true
    )
    let acceptanceEvidenceURL = acceptanceDirectory.appendingPathComponent("evaluation.json")
    try generatedArtifactCreateFile(at: acceptanceEvidenceURL)
    let acceptanceEvidence = try EvolutionAcceptanceEvidenceIntegrity().reference(
        for: acceptanceEvidenceURL,
        relativeTo: acceptanceDirectory,
        artifactType: "generated-test-evaluation"
    )
    let checkpointReference = try EvolutionCheckpointIntegrity().reference(
        checkpointID: "checkpoint-0",
        checkpointURL: checkpointURL,
        artifactRoot: directory
    )
    let acceptanceRecord = EvolutionCandidateAcceptanceRecord(
        runID: runID,
        generationIndex: 0,
        candidateID: candidateID,
        fitness: fitness,
        checkpointReference: checkpointReference,
        incumbentCandidateID: candidateID,
        incumbentFitness: fitness,
        incumbentCheckpointReference: checkpointReference,
        evaluationContract: EvolutionCandidateAcceptanceEvaluationContract(
            evaluatorID: "generated-test-evaluator",
            scenarioSuiteIDs: ["6"],
            episodesPerSuite: 1,
            determinismTier: "tier1",
            configurationDigest: String(repeating: "a", count: 64),
            evaluationFidelity: .fullScenario,
            workPhase: .candidateGate,
            worldExecutionRequirement: .preferAcceleratorSharedWorld
        ),
        evidence: [acceptanceEvidence],
        accepted: accepted,
        rejectionReasons: accepted ? [] : ["not-accepted"],
        completedAt: Date(timeIntervalSince1970: 2)
    )
    try EvolutionArtifactWriter().write(
        manifest: manifest,
        generations: [generation],
        candidates: [candidate],
        fitness: [fitness],
        eliteArchive: EvolutionEliteArchive(
            runID: runID,
            eliteCandidateIDs: [candidateID],
            bestCandidateID: candidateID,
            bestFitness: 1
        ),
        qualityDiversityArchive: EvolutionQualityDiversityArchive(
            runID: runID,
            descriptorKeys: ["taskPassRate"],
            cells: [
                EvolutionQualityDiversityCell(
                    cellID: "taskPassRate=1",
                    candidateID: candidateID,
                    generationIndex: 0,
                    fitness: 1,
                    behaviorDescriptor: ["taskPassRate": 1]
                )
            ]
        ),
        lineage: [
            EvolutionLineageRecord(
                runID: runID,
                generationIndex: 0,
                candidateID: candidateID,
                genomeID: "genome-0",
                parentCandidateIDs: []
            )
        ],
        evaluationTraces: [
            EvolutionCandidateEvaluationTrace(
                runID: runID,
                generationIndex: 0,
                candidateID: candidateID,
                requestedConcurrency: 1,
                activeEvaluationCountAtStart: 1,
                startedAt: Date(timeIntervalSince1970: 1),
                completedAt: Date(timeIntervalSince1970: 2)
            )
        ],
        acceptanceEvaluations: [acceptanceRecord],
        to: directory
    )
}

private func generatedArtifactProbeSummary(
    stage: TrainingProbeStage,
    passed: Bool
) throws -> TrainingProbeRunSummary {
    TrainingProbeRunSummary(
        stage: stage,
        output: try TrainingScenarioRunOutput(
            summary: TrainingScenarioRunSummary(
                suitePassed: passed,
                evaluations: [
                    TrainingScenarioEvaluationRecord(
                        scenarioID: "scenario-public-artifact",
                        seed: 1,
                        passed: passed,
                        maxOmega: 0.1,
                        maxTiltDegrees: passed ? 1 : 25,
                        sustainedViolationSeconds: passed ? 0 : 1,
                        recoveryTimeSeconds: passed ? 0.1 : nil,
                        overshootDegrees: passed ? 1 : 30,
                        hfStabilityScore: passed ? 0.9 : 0.1,
                        failures: passed ? [] : ["failed"]
                    )
                ],
                aggregate: TrainingScenarioEvaluationAggregate(
                    averageRecoveryTime: passed ? 0.1 : nil,
                    worstOvershootDegrees: passed ? 1 : 30,
                    averageHfStabilityScore: passed ? 0.9 : 0.1
                ),
                replay: try generatedArtifactReplayVerification(passed: true)
            ),
            logs: [],
            terminalFactsByScenarioKey: [:]
        )
    )
}

private func generatedArtifactScenarioRuns(runID: String) throws -> [TrainingScenarioRunArtifact] {
    [
        TrainingScenarioRunArtifact(
            runID: runID,
            iteration: 1,
            summary: TrainingScenarioRunSummary(
                suitePassed: true,
                evaluations: [
                    try TrainingScenarioEvaluationRecord(
                        scenarioID: "scenario-public-artifact",
                        seed: 1,
                        passed: true,
                        maxOmega: 0.1,
                        maxTiltDegrees: 1,
                        sustainedViolationSeconds: 0,
                        recoveryTimeSeconds: 0.1,
                        overshootDegrees: 1,
                        hfStabilityScore: 0.9,
                        failures: []
                    )
                ],
                aggregate: TrainingScenarioEvaluationAggregate(
                    averageRecoveryTime: 0.1,
                    worstOvershootDegrees: 1,
                    averageHfStabilityScore: 0.9
                ),
                replay: try generatedArtifactReplayVerification(passed: true)
            ),
            logCount: 1,
            terminalFactCount: 1
        )
    ]
}

private func generatedArtifactDatasetMetadata() -> TrainingDatasetMetadata {
    TrainingDatasetMetadata(
        scenarioId: "scenario-public-artifact",
        seed: 1,
        timeStep: 0.001,
        determinismTier: "tier1",
        configHash: "config-public-artifact",
        channelCount: 4,
        driveCount: 4,
        recordCount: 16,
        episodeId: "episode-public-artifact",
        rewardDescriptor: RewardDescriptor(id: "reward", version: "1", configHash: "reward-config"),
        provenance: TrainingProvenanceManifest(
            codeHash: "code",
            configHash: "config-public-artifact",
            robotManifestHash: "robot",
            suiteVersion: "suite-v1"
        )
    )
}

private func generatedArtifactCurriculum() -> LearningProjectCurriculum {
    LearningProjectCurriculum(
        suiteIDs: [0],
        seedCount: 1,
        episodesPerSuite: 1,
        populationSize: 4,
        generationLimit: 2,
        eliteCount: 1,
        maxStepCount: 128,
        trainingStages: [
            LearningProjectTrainingStage(
                stageID: "bootstrap",
                kind: .imitation,
                displayName: "Bootstrap",
                task: "attitude",
                taskProfileID: "reference.attitude",
                suiteIDs: [0],
                seedCount: 1,
                episodesPerSuite: 1,
                generationLimit: 1,
                executionMode: .sequential,
                dependsOnStageIDs: [],
                capabilities: [.stateEstimation]
            ),
            LearningProjectTrainingStage(
                stageID: "regression",
                kind: .regression,
                displayName: "Regression",
                task: "attitude",
                taskProfileID: "reference.attitude",
                suiteIDs: [0],
                seedCount: 1,
                episodesPerSuite: 1,
                generationLimit: 1,
                convergenceGoal: LearningProjectConvergenceGoal(kind: .validationGate, maxGenerationBudget: 1),
                executionMode: .sequential,
                dependsOnStageIDs: ["bootstrap"],
                capabilities: [.dynamicsStabilization]
            ),
        ]
    )
}

private func generatedArtifactCheckpointDecision(
    state: CheckpointDecisionState = .accepted,
    decidedAt: Date = Date(timeIntervalSince1970: 4)
) -> CheckpointDecision {
    CheckpointDecision(
        runID: "run-public-artifact",
        state: state,
        reason: state.rawValue,
        candidateCheckpointID: state == .failed || state == .skipped ? nil : "candidate",
        candidateCheckpointURL: state == .failed || state == .skipped ? nil : URL(fileURLWithPath: "/tmp/candidate"),
        publishedCheckpointURL: state == .accepted ? URL(fileURLWithPath: "/tmp/published") : nil,
        decidedAt: decidedAt
    )
}

private func generatedArtifactRegressionReference() -> TrainingProjectEvidencePack.RegressionArtifactReference {
    TrainingProjectEvidencePack.RegressionArtifactReference(
        kind: "checkpoint-evaluation",
        path: "evaluations/final/checkpoint-evaluation.json",
        accepted: true
    )
}

private func generatedArtifactObservabilityArtifact() -> ConsciousUnconsciousObservabilityArtifact {
    ConsciousUnconsciousObservabilityArtifact(
        runID: "run-public-artifact",
        scenarioID: "scenario-public-artifact",
        seed: 1,
        timeStep: 0.001,
        descendingSnapshots: [
            ConsciousUnconsciousObservabilityArtifact.DescendingSnapshot(
                stepIndex: 0,
                timestamp: 0,
                source: "planner",
                goalID: "hold-attitude",
                priority: 0.7,
                inhibition: 0.1,
                contextHash: "context-hash"
            ),
        ],
        upwardSummaries: [
            ConsciousUnconsciousObservabilityArtifact.UpwardSummary(
                stepIndex: 0,
                timestamp: 0,
                channels: [
                    ConsciousUnconsciousObservabilityArtifact.ScalarChannel(
                        name: "salience",
                        stableIndex: 0,
                        value: 0.4
                    ),
                    ConsciousUnconsciousObservabilityArtifact.ScalarChannel(
                        name: "risk",
                        stableIndex: 1,
                        value: 0.2
                    ),
                    ConsciousUnconsciousObservabilityArtifact.ScalarChannel(
                        name: "uncertainty",
                        stableIndex: 2,
                        value: 0.3
                    ),
                    ConsciousUnconsciousObservabilityArtifact.ScalarChannel(
                        name: "constraintPressure",
                        stableIndex: 3,
                        value: 0.5
                    ),
                    ConsciousUnconsciousObservabilityArtifact.ScalarChannel(
                        name: "recoveryState",
                        stableIndex: 4,
                        value: 0.8
                    ),
                ]
            ),
        ],
        arbitrationDecisions: [
            ConsciousUnconsciousObservabilityArtifact.ArbitrationDecision(
                stepIndex: 0,
                timestamp: 0,
                coreDriveMagnitude: 0.7,
                reflexCorrectionMagnitude: 0.3,
                finalDriveMagnitude: 0.5,
                reflexPreemptedDescendingBias: true,
                reason: "reflex reduced conflicting descending priority"
            ),
        ],
        latencyBudgetViolations: [
            ConsciousUnconsciousObservabilityArtifact.LatencyBudgetViolation(
                stepIndex: 0,
                timestamp: 0,
                path: "summaryExport",
                budgetMilliseconds: 2,
                observedMilliseconds: 3,
                reason: "observed summary export exceeded budget"
            ),
        ]
    )
}

private func generatedArtifactReplayVerification(passed: Bool) throws -> ReplayVerification {
    .performed([
        ReplayCheckResult(
            scenarioId: try ScenarioID("scenario-public-artifact"),
            seed: ScenarioSeed(1),
            tier: .tier0,
            passed: passed,
            issues: passed ? [] : ["failed"],
            residuals: .zero
        )
    ])
}

private func generatedArtifactDescriptorCorpusSummary(
    requiredReadiness: ReadinessLevel = .dynamicSimulation,
    hardwareParity: DescriptorCorpusHardwareParityStatus = .notRequested,
    hardwareEvidence: DescriptorCorpusHardwareEvidence? = nil,
    contactReplay: DescriptorCorpusContactReplayEvidence? = nil
) -> DescriptorCorpusAcceptanceSummary {
    DescriptorCorpusAcceptanceSummary(
        corpusID: "generated-artifact-physics-corpus",
        generatedAt: "1970-01-01T00:00:00Z",
        records: [
            DescriptorCorpusAcceptanceRecord(
                entryID: "generated-artifact-physics-entry",
                robotID: "reference-robot",
                label: "Reference Robot",
                bodyID: "reference-body",
                worldID: "reference-world",
                embodimentContractID: "reference-embodiment",
                requiredReadiness: requiredReadiness,
                achievedReadiness: requiredReadiness,
                hardwareParity: hardwareParity,
                hardwareEvidence: hardwareEvidence,
                readinessGaps: [],
                replay: DescriptorCorpusReplayEvidence(
                    passed: true,
                    tier: .tier1,
                    stepCount: 16,
                    configHash: "physics-config",
                    sortedJSONByteStable: true,
                    issues: [],
                    residuals: .zero,
                    contact: contactReplay
                )
            ),
        ]
    )
}

private func generatedArtifactContactReplayEvidence() -> DescriptorCorpusContactReplayEvidence {
    DescriptorCorpusContactReplayEvidence(
        maxActiveContactCount: 2,
        maxPenetration: 0.001,
        maxNormalImpulse: 0.02,
        maxNormalForce: 0.3,
        maxSolverIterations: 4
    )
}

private func generatedArtifactHardwareEvidence(reportHash: String) -> DescriptorCorpusHardwareEvidence {
    DescriptorCorpusHardwareEvidence(
        reportID: "generated-hardware-report",
        robotID: "reference-robot",
        bodyID: "reference-body",
        embodimentContractID: "reference-embodiment",
        reportHash: reportHash,
        readinessLevel: .hardwareParity,
        measurementSystem: "bench-measurement",
        deviceID: "measurement-device-a",
        jointCalibrationCount: 1,
        jointSampleCount: 3,
        measuredJointSampleCount: 3,
        observedJointSampleCount: 3,
        contactCalibrationCount: 0,
        contactSampleCount: 0
    )
}

private func generatedArtifactCreateFile(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{}".write(to: url, atomically: true, encoding: .utf8)
}

private func generatedArtifactWriteJSON<T: Encodable>(_ value: T, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: url, options: [.atomic])
}

private func generatedArtifactTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-generated-artifact-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func generatedArtifactCleanup(_ directory: URL) {
    do {
        try FileManager.default.removeItem(at: directory)
    } catch {
        Issue.record("Failed to remove temporary directory: \(error)")
    }
}
