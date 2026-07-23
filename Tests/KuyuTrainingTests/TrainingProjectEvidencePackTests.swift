import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTraining
import Testing

@Test func trainingProjectEvidencePackValidatorBuildsEvidencePack() throws {
    let validator = TrainingProjectEvidencePackValidator()
    let pack = try validator.makePack(
        projectID: "reference-foundation",
        datasetMetadata: [projectEvidenceMetadata(id: "episode-a"), projectEvidenceMetadata(id: "episode-b", seed: 2)],
        curriculum: projectEvidenceCurriculum(),
        checkpointDecision: projectEvidenceAcceptedCheckpointDecision(),
        regressionArtifacts: [
            TrainingProjectEvidencePack.RegressionArtifactReference(
                kind: "checkpoint-evaluation",
                path: "evaluations/final/checkpoint-evaluation.json",
                accepted: true
            ),
            TrainingProjectEvidencePack.RegressionArtifactReference(
                kind: "stress-suite",
                path: "stress/reference-attitude.json",
                accepted: true
            ),
        ],
        createdAt: Date(timeIntervalSince1970: 100)
    )

    #expect(pack.schemaVersion == TrainingProjectEvidencePack.currentSchemaVersion)
    #expect(pack.datasets.map(\.datasetID) == ["episode-a", "episode-b"])
    #expect(pack.curriculumStages.map(\.stageID) == ["bootstrap", "regression"])
    #expect(pack.checkpoint.state == .accepted)
    #expect(pack.regressionArtifacts.count == 2)
}

@Test func trainingProjectEvidencePackValidatorRejectsDuplicateDatasets() throws {
    let pack = TrainingProjectEvidencePack(
        projectID: "reference-foundation",
        createdAt: Date(timeIntervalSince1970: 100),
        datasets: [
            TrainingProjectEvidencePack.DatasetLineageRecord(metadata: projectEvidenceMetadata(id: "episode-a")),
            TrainingProjectEvidencePack.DatasetLineageRecord(metadata: projectEvidenceMetadata(id: "episode-a", seed: 2)),
        ],
        curriculumStages: projectEvidenceCurriculum().trainingStages.map(
            TrainingProjectEvidencePack.CurriculumStageEvidence.init
        ),
        checkpoint: TrainingProjectEvidencePack.CheckpointEvidence(decision: projectEvidenceAcceptedCheckpointDecision()),
        regressionArtifacts: [projectEvidenceRegressionArtifact()]
    )

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError.duplicateDatasetID("episode-a")) {
        try TrainingProjectEvidencePackValidator().validate(pack)
    }
}

@Test func trainingProjectEvidencePackValidatorRejectsMissingStageDependency() throws {
    let pack = TrainingProjectEvidencePack(
        projectID: "reference-foundation",
        createdAt: Date(timeIntervalSince1970: 100),
        datasets: [TrainingProjectEvidencePack.DatasetLineageRecord(metadata: projectEvidenceMetadata(id: "episode-a"))],
        curriculumStages: [
            TrainingProjectEvidencePack.CurriculumStageEvidence(
                stageID: "regression",
                kind: .regression,
                task: "attitude",
                taskProfileID: "reference.attitude",
                suiteIDs: [0],
                seedCount: 1,
                episodesPerSuite: 1,
                generationLimit: 1,
                dependsOnStageIDs: ["bootstrap"]
            ),
        ],
        checkpoint: TrainingProjectEvidencePack.CheckpointEvidence(decision: projectEvidenceAcceptedCheckpointDecision()),
        regressionArtifacts: [projectEvidenceRegressionArtifact()]
    )

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError.missingStageDependency(
        stageID: "regression",
        dependencyID: "bootstrap"
    )) {
        try TrainingProjectEvidencePackValidator().validate(pack)
    }
}

@Test func trainingProjectEvidencePackValidatorRejectsEmptyProducedArtifactID() throws {
    let pack = TrainingProjectEvidencePack(
        projectID: "reference-foundation",
        createdAt: Date(timeIntervalSince1970: 100),
        datasets: [TrainingProjectEvidencePack.DatasetLineageRecord(metadata: projectEvidenceMetadata(id: "episode-a"))],
        curriculumStages: [
            TrainingProjectEvidencePack.CurriculumStageEvidence(
                stageID: "world-model",
                kind: .worldModel,
                task: "world-model-prediction",
                taskProfileID: nil,
                producedArtifactID: " ",
                suiteIDs: [0],
                seedCount: 1,
                episodesPerSuite: 1,
                generationLimit: 1,
                dependsOnStageIDs: []
            ),
        ],
        checkpoint: TrainingProjectEvidencePack.CheckpointEvidence(decision: projectEvidenceAcceptedCheckpointDecision()),
        regressionArtifacts: [projectEvidenceRegressionArtifact()]
    )

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError.emptyProducedArtifactID(
        stageID: "world-model"
    )) {
        try TrainingProjectEvidencePackValidator().validate(pack)
    }
}

@Test func trainingProjectEvidencePackValidatorRejectsAcceptedCheckpointWithoutPublication() throws {
    let pack = TrainingProjectEvidencePack(
        projectID: "reference-foundation",
        createdAt: Date(timeIntervalSince1970: 100),
        datasets: [TrainingProjectEvidencePack.DatasetLineageRecord(metadata: projectEvidenceMetadata(id: "episode-a"))],
        curriculumStages: projectEvidenceCurriculum().trainingStages.map(
            TrainingProjectEvidencePack.CurriculumStageEvidence.init
        ),
        checkpoint: TrainingProjectEvidencePack.CheckpointEvidence(
            runID: "run-a",
            state: .accepted,
            reason: "accepted",
            candidateCheckpointID: "candidate-a",
            hasCandidateCheckpointURL: true,
            hasPublishedCheckpointURL: false
        ),
        regressionArtifacts: [projectEvidenceRegressionArtifact()]
    )

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError.acceptedCheckpointMissingPublishedURL) {
        try TrainingProjectEvidencePackValidator().validate(pack)
    }
}

@Test func trainingProjectEvidencePackDecodeRejectsAbsoluteRegressionArtifactPath() throws {
    let pack = TrainingProjectEvidencePack(
        projectID: "reference-foundation",
        createdAt: Date(timeIntervalSince1970: 100),
        datasets: [TrainingProjectEvidencePack.DatasetLineageRecord(metadata: projectEvidenceMetadata(id: "episode-a"))],
        curriculumStages: projectEvidenceCurriculum().trainingStages.map(
            TrainingProjectEvidencePack.CurriculumStageEvidence.init
        ),
        checkpoint: TrainingProjectEvidencePack.CheckpointEvidence(decision: projectEvidenceAcceptedCheckpointDecision()),
        regressionArtifacts: [
            TrainingProjectEvidencePack.RegressionArtifactReference(
                kind: "checkpoint-evaluation",
                path: "/tmp/checkpoint-evaluation.json",
                accepted: true
            ),
        ]
    )
    let data = try JSONEncoder().encode(pack)

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError.absoluteRegressionArtifactPath(
        "/tmp/checkpoint-evaluation.json"
    )) {
        _ = try JSONDecoder().decode(TrainingProjectEvidencePack.self, from: data)
    }
}

@Test func trainingProjectEvidencePackStoreWritesAndReloadsValidatedPack() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    defer { projectEvidenceCleanup(directory) }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )

    let pack = try TrainingProjectEvidencePackArtifactStore().writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [projectEvidenceMetadata(id: "episode-a")],
        curriculum: projectEvidenceCurriculum(),
        checkpointDecision: projectEvidenceAcceptedCheckpointDecision(),
        regressionArtifacts: [projectEvidenceRegressionArtifact()],
        to: directory,
        createdAt: Date(timeIntervalSince1970: 100)
    )

    #expect(pack.projectID == "reference-foundation")
    #expect(pack.datasets.map(\.datasetID) == ["episode-a"])
    #expect(pack.regressionArtifacts.map(\.path) == ["evaluations/final/checkpoint-evaluation.json"])
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(
        TrainingProjectEvidencePack.fileName
    ).path))
}

@Test func trainingProjectEvidencePackStoreRejectsMissingReferencedArtifact() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    defer { projectEvidenceCleanup(directory) }
    let pack = TrainingProjectEvidencePack(
        projectID: "reference-foundation",
        createdAt: Date(timeIntervalSince1970: 100),
        datasets: [TrainingProjectEvidencePack.DatasetLineageRecord(metadata: projectEvidenceMetadata(id: "episode-a"))],
        curriculumStages: projectEvidenceCurriculum().trainingStages.map(
            TrainingProjectEvidencePack.CurriculumStageEvidence.init
        ),
        checkpoint: TrainingProjectEvidencePack.CheckpointEvidence(decision: projectEvidenceAcceptedCheckpointDecision()),
        regressionArtifacts: [projectEvidenceRegressionArtifact()]
    )

    #expect(throws: TrainingProjectEvidencePackArtifactStore.StoreError.missingReferencedRegressionArtifact(
        "evaluations/final/checkpoint-evaluation.json"
    )) {
        _ = try TrainingProjectEvidencePackArtifactStore().write(pack, to: directory)
    }
}

@Test func trainingProjectEvidencePackStoreRejectsMissingPackFile() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    defer { projectEvidenceCleanup(directory) }

    let expected = directory.appendingPathComponent(TrainingProjectEvidencePack.fileName).path
    #expect(throws: TrainingProjectEvidencePackArtifactStore.StoreError.missingEvidencePack(expected)) {
        _ = try TrainingProjectEvidencePackArtifactStore().load(from: directory)
    }
}

@Test func trainingProjectEvidencePackStoreRejectsEvidencePackSymlinkEscape() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    let externalDirectory = try projectEvidenceTemporaryDirectory()
    defer {
        projectEvidenceCleanup(directory)
        projectEvidenceCleanup(externalDirectory)
    }
    let linkURL = directory.appendingPathComponent(TrainingProjectEvidencePack.fileName)
    let externalPackURL = externalDirectory.appendingPathComponent(TrainingProjectEvidencePack.fileName)
    try projectEvidenceCreateFile(at: externalPackURL)
    try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: externalPackURL)

    #expect(throws: TrainingProjectEvidencePackArtifactStore.StoreError.evidencePackEscapesRoot(
        linkURL.path
    )) {
        _ = try TrainingProjectEvidencePackArtifactStore().load(from: directory)
    }
}

@Test func trainingProjectEvidencePackStoreRejectsRegressionArtifactSymlinkEscape() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    let externalDirectory = try projectEvidenceTemporaryDirectory()
    defer {
        projectEvidenceCleanup(directory)
        projectEvidenceCleanup(externalDirectory)
    }
    let artifactPath = "evaluations/final/checkpoint-evaluation.json"
    let linkURL = directory.appendingPathComponent(artifactPath)
    let externalArtifactURL = externalDirectory.appendingPathComponent("checkpoint-evaluation.json")
    try projectEvidenceCreateFile(at: externalArtifactURL)
    try FileManager.default.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: externalArtifactURL)
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        regressionArtifacts: [projectEvidenceRegressionArtifact(path: artifactPath)]
    )

    #expect(throws: TrainingProjectEvidencePackArtifactStore.StoreError
        .referencedRegressionArtifactEscapesRoot(artifactPath)) {
        _ = try TrainingProjectEvidencePackArtifactStore().write(pack, to: directory)
    }
}

@Test func trainingProjectEvidencePackStoreRejectsRegressionArtifactDirectorySymlinkEscape() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    let externalDirectory = try projectEvidenceTemporaryDirectory()
    defer {
        projectEvidenceCleanup(directory)
        projectEvidenceCleanup(externalDirectory)
    }
    let artifactPath = "evaluations/final/checkpoint-evaluation.json"
    try projectEvidenceCreateFile(
        at: externalDirectory.appendingPathComponent("final/checkpoint-evaluation.json")
    )
    try FileManager.default.createSymbolicLink(
        at: directory.appendingPathComponent("evaluations", isDirectory: true),
        withDestinationURL: externalDirectory
    )
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        regressionArtifacts: [projectEvidenceRegressionArtifact(path: artifactPath)]
    )

    #expect(throws: TrainingProjectEvidencePackArtifactStore.StoreError
        .referencedRegressionArtifactEscapesRoot(artifactPath)) {
        _ = try TrainingProjectEvidencePackArtifactStore().write(pack, to: directory)
    }
}

@Test func trainingProjectEvidencePackStoreWritesAndReloadsStressSuiteEvidence() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    defer { projectEvidenceCleanup(directory) }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let manifest = try projectEvidenceStressManifest()
    let stressPath = "stress/reference-attitude-stress.json"
    try projectEvidenceWriteJSON(manifest, to: directory.appendingPathComponent(stressPath))
    let stressEvidence = TrainingProjectEvidencePack.StressSuiteEvidence(
        manifest: manifest,
        path: stressPath
    )
    let loaded = try TrainingProjectEvidencePackArtifactStore().writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [projectEvidenceMetadata(id: "episode-a")],
        curriculum: projectEvidenceCurriculum(),
        checkpointDecision: projectEvidenceAcceptedCheckpointDecision(),
        regressionArtifacts: [projectEvidenceRegressionArtifact()],
        stressSuites: [stressEvidence],
        to: directory,
        createdAt: Date(timeIntervalSince1970: 100)
    )

    #expect(loaded.stressSuites == [stressEvidence])
    #expect(loaded.stressSuites.first?.coverageTargets.contains {
        $0.dimension == .longHorizon
    } == true)
}

@Test func trainingProjectEvidencePackStoreWritesAndReloadsReferenceM2SemanticStressSuiteEvidence() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    defer { projectEvidenceCleanup(directory) }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let manifest = try projectEvidenceM2StressManifest()
    let stressPath = "stress/reference-m2-stress.json"
    try projectEvidenceWriteJSON(manifest, to: directory.appendingPathComponent(stressPath))
    let stressEvidence = TrainingProjectEvidencePack.StressSuiteEvidence(
        manifest: manifest,
        path: stressPath
    )
    let loaded = try TrainingProjectEvidencePackArtifactStore().writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [projectEvidenceMetadata(id: "episode-a")],
        curriculum: projectEvidenceCurriculum(),
        checkpointDecision: projectEvidenceAcceptedCheckpointDecision(),
        regressionArtifacts: [projectEvidenceRegressionArtifact()],
        stressSuites: [stressEvidence],
        to: directory,
        createdAt: Date(timeIntervalSince1970: 100)
    )

    let loadedStress = try #require(loaded.stressSuites.first)
    #expect(loadedStress.coversReferenceM2Benchmark)
    #expect(loadedStress.referenceM2BenchmarkEvidence?.isComplete == true)
    #expect(loadedStress.referenceM2BenchmarkEvidence?.plannerDegradationScenarioIDs == ["LH-TASK-0"])
    #expect(loadedStress.referenceM2BenchmarkEvidence?.morphologyTransfers.first?.parameterDeltas.isEmpty == false)
}

@Test func trainingProjectEvidencePackStoreRejectsMismatchedReferenceM2PlannerEvidence() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    defer { projectEvidenceCleanup(directory) }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let manifest = try projectEvidenceM2StressManifest()
    let stressPath = "stress/reference-m2-stress.json"
    try projectEvidenceWriteJSON(manifest, to: directory.appendingPathComponent(stressPath))
    let validStressEvidence = TrainingProjectEvidencePack.StressSuiteEvidence(
        manifest: manifest,
        path: stressPath
    )
    let validReferenceEvidence = try #require(validStressEvidence.referenceM2BenchmarkEvidence)
    let replacementPlannerID = try #require(validReferenceEvidence.morphologyTransfers.first?.scenarioID)
    let staleReferenceEvidence = try StressSuiteManifest.ReferenceM2BenchmarkEvidence(
        tracks: validReferenceEvidence.tracks,
        plannerDegradationScenarioIDs: [replacementPlannerID],
        morphologyTransfers: validReferenceEvidence.morphologyTransfers,
        disturbanceScenarioIDs: validReferenceEvidence.disturbanceScenarioIDs,
        latencyScenarioIDs: validReferenceEvidence.latencyScenarioIDs,
        partialObservabilityScenarioIDs: validReferenceEvidence.partialObservabilityScenarioIDs
    )
    let staleStressEvidence = TrainingProjectEvidencePack.StressSuiteEvidence(
        suiteID: validStressEvidence.suiteID,
        profile: validStressEvidence.profile,
        recordCount: validStressEvidence.recordCount,
        coverageTargets: validStressEvidence.coverageTargets,
        replayStatus: validStressEvidence.replayStatus,
        replayCheckCount: validStressEvidence.replayCheckCount,
        referenceM2BenchmarkEvidence: staleReferenceEvidence,
        path: validStressEvidence.path
    )
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        stressSuites: [staleStressEvidence]
    )

    #expect(throws: TrainingProjectEvidencePackArtifactStore.StoreError
        .referencedStressSuiteManifestMismatch(stressPath)) {
        _ = try TrainingProjectEvidencePackArtifactStore().write(pack, to: directory)
    }
}

@Test func trainingProjectEvidencePackStoreRejectsMismatchedStressSuiteEvidence() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    defer { projectEvidenceCleanup(directory) }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let manifest = try projectEvidenceStressManifest(suiteID: "reference-attitude-stress")
    let replacementManifest = try projectEvidenceStressManifest(suiteID: "different-stress")
    let stressPath = "stress/reference-attitude-stress.json"
    try projectEvidenceWriteJSON(replacementManifest, to: directory.appendingPathComponent(stressPath))
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        stressSuites: [
            TrainingProjectEvidencePack.StressSuiteEvidence(
                manifest: manifest,
                path: stressPath
            ),
        ]
    )

    #expect(throws: TrainingProjectEvidencePackArtifactStore.StoreError
        .referencedStressSuiteManifestMismatch(stressPath)) {
        _ = try TrainingProjectEvidencePackArtifactStore().write(pack, to: directory)
    }
}

@Test func trainingProjectEvidencePackStoreRejectsStressSuiteSymlinkEscape() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    let externalDirectory = try projectEvidenceTemporaryDirectory()
    defer {
        projectEvidenceCleanup(directory)
        projectEvidenceCleanup(externalDirectory)
    }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let manifest = try projectEvidenceStressManifest()
    let stressPath = "stress/reference-attitude-stress.json"
    let linkURL = directory.appendingPathComponent(stressPath)
    let externalStressURL = externalDirectory.appendingPathComponent("reference-attitude-stress.json")
    try projectEvidenceWriteJSON(manifest, to: externalStressURL)
    try FileManager.default.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: externalStressURL)
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        stressSuites: [TrainingProjectEvidencePack.StressSuiteEvidence(
            manifest: manifest,
            path: stressPath
        )]
    )

    #expect(throws: TrainingProjectEvidencePackArtifactStore.StoreError
        .referencedStressSuiteManifestEscapesRoot(stressPath)) {
        _ = try TrainingProjectEvidencePackArtifactStore().write(pack, to: directory)
    }
}

@Test func trainingProjectEvidencePackStoreRejectsStressSuiteDirectorySymlinkEscape() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    let externalDirectory = try projectEvidenceTemporaryDirectory()
    defer {
        projectEvidenceCleanup(directory)
        projectEvidenceCleanup(externalDirectory)
    }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let manifest = try projectEvidenceStressManifest()
    let stressPath = "stress/reference-attitude-stress.json"
    let externalStressURL = externalDirectory.appendingPathComponent(
        "reference-attitude-stress.json",
        isDirectory: false
    )
    try projectEvidenceWriteJSON(manifest, to: externalStressURL)
    let symlinkDirectory = directory.appendingPathComponent("stress", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: symlinkDirectory, withDestinationURL: externalDirectory)
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        stressSuites: [TrainingProjectEvidencePack.StressSuiteEvidence(
            manifest: manifest,
            path: stressPath
        )]
    )

    #expect(throws: TrainingProjectEvidencePackArtifactStore.StoreError
        .referencedStressSuiteManifestEscapesRoot(stressPath)) {
        _ = try TrainingProjectEvidencePackArtifactStore().write(pack, to: directory)
    }
}

@Test func trainingProjectEvidencePackStoreWritesAndReloadsPhysicsCorpusEvidence() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    defer { projectEvidenceCleanup(directory) }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let summary = projectEvidenceDescriptorCorpusSummary()
    let physicsPath = "physics/descriptor-corpus-acceptance.json"
    try projectEvidenceWriteJSON(summary, to: directory.appendingPathComponent(physicsPath))
    let physicsEvidence = TrainingProjectEvidencePack.PhysicsCorpusEvidence(
        summary: summary,
        path: physicsPath
    )

    let loaded = try TrainingProjectEvidencePackArtifactStore().writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [projectEvidenceMetadata(id: "episode-a")],
        curriculum: projectEvidenceCurriculum(),
        checkpointDecision: projectEvidenceAcceptedCheckpointDecision(),
        regressionArtifacts: [projectEvidenceRegressionArtifact()],
        stressSuites: [],
        physicsCorpora: [physicsEvidence],
        to: directory,
        createdAt: Date(timeIntervalSince1970: 100)
    )

    #expect(loaded.physicsCorpora == [physicsEvidence])
    #expect(loaded.physicsCorpora.first?.requiredReadinessLevels == [.dynamicSimulation])
    #expect(loaded.physicsCorpora.first?.hardwareEvidenceRecordCount == 0)
    #expect(loaded.physicsCorpora.first?.acceptedHardwareParityRecordCount == 0)
    #expect(loaded.physicsCorpora.first?.hardwareEvidenceReportHashes == [])
}

@Test func trainingProjectEvidencePackStoreSummarizesHardwareCorpusEvidence() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    defer { projectEvidenceCleanup(directory) }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let summary = projectEvidenceDescriptorCorpusSummary(
        requiredReadiness: .hardwareParity,
        hardwareParity: .accepted,
        hardwareEvidence: projectEvidenceHardwareEvidence(reportHash: "hardware-report-hash-a")
    )
    let physicsPath = "physics/descriptor-corpus-acceptance.json"
    try projectEvidenceWriteJSON(summary, to: directory.appendingPathComponent(physicsPath))
    let physicsEvidence = TrainingProjectEvidencePack.PhysicsCorpusEvidence(
        summary: summary,
        path: physicsPath
    )

    let loaded = try TrainingProjectEvidencePackArtifactStore().writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [projectEvidenceMetadata(id: "episode-a")],
        curriculum: projectEvidenceCurriculum(),
        checkpointDecision: projectEvidenceAcceptedCheckpointDecision(),
        regressionArtifacts: [projectEvidenceRegressionArtifact()],
        stressSuites: [],
        physicsCorpora: [physicsEvidence],
        to: directory,
        createdAt: Date(timeIntervalSince1970: 100)
    )

    #expect(loaded.physicsCorpora.first?.acceptedRecordCount == 1)
    #expect(loaded.physicsCorpora.first?.requiredReadinessLevels == [.hardwareParity])
    #expect(loaded.physicsCorpora.first?.hardwareParityGapCount == 0)
    #expect(loaded.physicsCorpora.first?.hardwareEvidenceRecordCount == 1)
    #expect(loaded.physicsCorpora.first?.acceptedHardwareParityRecordCount == 1)
    #expect(loaded.physicsCorpora.first?.hardwareEvidenceReportHashes == ["hardware-report-hash-a"])
    #expect(loaded.physicsCorpora.first?.hardwareEvidenceMeasurementSystems == ["bench-measurement"])
    #expect(loaded.physicsCorpora.first?.hardwareEvidenceDeviceIDs == ["measurement-device-a"])
    #expect(loaded.physicsCorpora.first?.hardwareJointCalibrationRecordCount == 1)
    #expect(loaded.physicsCorpora.first?.hardwareJointSampleCount == 3)
    #expect(loaded.physicsCorpora.first?.measuredHardwareJointSampleCount == 3)
    #expect(loaded.physicsCorpora.first?.observedHardwareJointSampleCount == 3)
    #expect(loaded.physicsCorpora.first?.hardwareSensorCalibrationRecordCount == 0)
    #expect(loaded.physicsCorpora.first?.hardwareSensorSampleCount == 0)
    #expect(loaded.physicsCorpora.first?.observedHardwareSensorSampleCount == 0)
}

@Test func trainingProjectEvidencePackStoreSummarizesHardwareSensorCorpusEvidence() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    defer { projectEvidenceCleanup(directory) }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let summary = projectEvidenceDescriptorCorpusSummary(
        requiredReadiness: .hardwareParity,
        hardwareParity: .accepted,
        hardwareEvidence: projectEvidenceHardwareEvidence(
            reportHash: "hardware-report-hash-a",
            sensorCalibrationCount: 1,
            sensorSampleCount: 3,
            observedSensorSampleCount: 3
        )
    )
    let physicsPath = "physics/descriptor-corpus-acceptance.json"
    try projectEvidenceWriteJSON(summary, to: directory.appendingPathComponent(physicsPath))
    let physicsEvidence = TrainingProjectEvidencePack.PhysicsCorpusEvidence(
        summary: summary,
        path: physicsPath
    )

    let loaded = try TrainingProjectEvidencePackArtifactStore().writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [projectEvidenceMetadata(id: "episode-a")],
        curriculum: projectEvidenceCurriculum(),
        checkpointDecision: projectEvidenceAcceptedCheckpointDecision(),
        regressionArtifacts: [projectEvidenceRegressionArtifact()],
        stressSuites: [],
        physicsCorpora: [physicsEvidence],
        to: directory,
        createdAt: Date(timeIntervalSince1970: 100)
    )

    #expect(loaded.physicsCorpora.first?.hardwareEvidenceRecordCount == 1)
    #expect(loaded.physicsCorpora.first?.acceptedHardwareParityRecordCount == 1)
    #expect(loaded.physicsCorpora.first?.hardwareSensorCalibrationRecordCount == 1)
    #expect(loaded.physicsCorpora.first?.hardwareSensorSampleCount == 3)
    #expect(loaded.physicsCorpora.first?.observedHardwareSensorSampleCount == 3)
}

@Test func trainingProjectEvidencePackStoreSummarizesContactTrainingCorpusEvidence() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    defer { projectEvidenceCleanup(directory) }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let summary = projectEvidenceDescriptorCorpusSummary(
        requiredReadiness: .contactTraining,
        contactReplay: projectEvidenceContactReplayEvidence()
    )
    let physicsPath = "physics/descriptor-corpus-acceptance.json"
    try projectEvidenceWriteJSON(summary, to: directory.appendingPathComponent(physicsPath))
    let physicsEvidence = TrainingProjectEvidencePack.PhysicsCorpusEvidence(
        summary: summary,
        path: physicsPath
    )

    let loaded = try TrainingProjectEvidencePackArtifactStore().writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [projectEvidenceMetadata(id: "episode-a")],
        curriculum: projectEvidenceCurriculum(),
        checkpointDecision: projectEvidenceAcceptedCheckpointDecision(),
        regressionArtifacts: [projectEvidenceRegressionArtifact()],
        stressSuites: [],
        physicsCorpora: [physicsEvidence],
        to: directory,
        createdAt: Date(timeIntervalSince1970: 100)
    )

    #expect(loaded.physicsCorpora.first?.acceptedRecordCount == 1)
    #expect(loaded.physicsCorpora.first?.requiredReadinessLevels == [.contactTraining])
    #expect(loaded.physicsCorpora.first?.contactReplayRecordCount == 1)
    #expect(loaded.physicsCorpora.first?.hardwareEvidenceRecordCount == 0)
}

@Test func trainingProjectEvidencePackStoreRejectsMismatchedPhysicsCorpusEvidence() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    defer { projectEvidenceCleanup(directory) }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let expectedSummary = projectEvidenceDescriptorCorpusSummary(corpusID: "reference-physics-corpus")
    let replacementSummary = projectEvidenceDescriptorCorpusSummary(corpusID: "different-physics-corpus")
    let physicsPath = "physics/descriptor-corpus-acceptance.json"
    try projectEvidenceWriteJSON(replacementSummary, to: directory.appendingPathComponent(physicsPath))
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        physicsCorpora: [
            TrainingProjectEvidencePack.PhysicsCorpusEvidence(
                summary: expectedSummary,
                path: physicsPath
            ),
        ]
    )

    #expect(throws: TrainingProjectEvidencePackArtifactStore.StoreError
        .referencedPhysicsCorpusAcceptanceMismatch(physicsPath)) {
        _ = try TrainingProjectEvidencePackArtifactStore().write(pack, to: directory)
    }
}

@Test func trainingProjectEvidencePackStoreRejectsStaleHardwareCorpusEvidence() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    defer { projectEvidenceCleanup(directory) }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let summary = projectEvidenceDescriptorCorpusSummary(
        requiredReadiness: .hardwareParity,
        hardwareParity: .accepted,
        hardwareEvidence: projectEvidenceHardwareEvidence(reportHash: "hardware-report-hash-a")
    )
    let physicsPath = "physics/descriptor-corpus-acceptance.json"
    try projectEvidenceWriteJSON(summary, to: directory.appendingPathComponent(physicsPath))
    let staleEvidence = TrainingProjectEvidencePack.PhysicsCorpusEvidence(
        corpusID: summary.corpusID,
        acceptedRecordCount: 1,
        hardwareParityGapCount: 0,
        requiredReadinessLevels: [.hardwareParity],
        hardwareEvidenceRecordCount: 1,
        acceptedHardwareParityRecordCount: 1,
        hardwareEvidenceReportHashes: ["stale-hardware-report-hash"],
        hardwareEvidenceMeasurementSystems: ["bench-measurement"],
        hardwareEvidenceDeviceIDs: ["measurement-device-a"],
        hardwareJointCalibrationRecordCount: 1,
        hardwareJointSampleCount: 3,
        measuredHardwareJointSampleCount: 3,
        observedHardwareJointSampleCount: 3,
        path: physicsPath
    )
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        physicsCorpora: [staleEvidence]
    )

    #expect(throws: TrainingProjectEvidencePackArtifactStore.StoreError
        .referencedPhysicsCorpusAcceptanceMismatch(physicsPath)) {
        _ = try TrainingProjectEvidencePackArtifactStore().write(pack, to: directory)
    }
}

@Test func trainingProjectEvidencePackValidatorRejectsImpossibleHardwareCorpusCounts() throws {
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        physicsCorpora: [
            TrainingProjectEvidencePack.PhysicsCorpusEvidence(
                corpusID: "reference-physics-corpus",
                acceptedRecordCount: 1,
                hardwareParityGapCount: 0,
                requiredReadinessLevels: [.hardwareParity],
                hardwareEvidenceRecordCount: 0,
                acceptedHardwareParityRecordCount: 1,
                hardwareEvidenceReportHashes: [],
                path: "physics/descriptor-corpus-acceptance.json"
            ),
        ]
    )

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError
        .invalidPhysicsCorpusAcceptedHardwareParityRecordCount(
            corpusID: "reference-physics-corpus",
            acceptedHardwareParityRecordCount: 1
        )) {
        try TrainingProjectEvidencePackValidator().validate(pack)
    }
}

@Test func trainingProjectEvidencePackValidatorRejectsHardwareEvidenceWithoutMeasurementSystem() throws {
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        physicsCorpora: [
            TrainingProjectEvidencePack.PhysicsCorpusEvidence(
                corpusID: "reference-physics-corpus",
                acceptedRecordCount: 1,
                hardwareParityGapCount: 0,
                requiredReadinessLevels: [.dynamicSimulation],
                hardwareEvidenceRecordCount: 1,
                acceptedHardwareParityRecordCount: 0,
                hardwareEvidenceReportHashes: ["hardware-report-hash-a"],
                hardwareEvidenceMeasurementSystems: [],
                path: "physics/descriptor-corpus-acceptance.json"
            ),
        ]
    )

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError
        .emptyPhysicsCorpusHardwareEvidenceMeasurementSystem("reference-physics-corpus")) {
        try TrainingProjectEvidencePackValidator().validate(pack)
    }
}

@Test func trainingProjectEvidencePackValidatorRejectsHardwareParityReadinessWithoutAcceptedEvidence() throws {
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        physicsCorpora: [
            TrainingProjectEvidencePack.PhysicsCorpusEvidence(
                corpusID: "reference-physics-corpus",
                acceptedRecordCount: 1,
                hardwareParityGapCount: 0,
                requiredReadinessLevels: [.hardwareParity],
                hardwareEvidenceRecordCount: 0,
                acceptedHardwareParityRecordCount: 0,
                hardwareEvidenceReportHashes: [],
                path: "physics/descriptor-corpus-acceptance.json"
            ),
        ]
    )

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError
        .missingPhysicsCorpusHardwareParityEvidence("reference-physics-corpus")) {
        try TrainingProjectEvidencePackValidator().validate(pack)
    }
}

@Test func trainingProjectEvidencePackValidatorRejectsHardwareParityWithoutMeasuredJointEvidence() throws {
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        physicsCorpora: [
            TrainingProjectEvidencePack.PhysicsCorpusEvidence(
                corpusID: "reference-physics-corpus",
                acceptedRecordCount: 1,
                hardwareParityGapCount: 0,
                requiredReadinessLevels: [.hardwareParity],
                hardwareEvidenceRecordCount: 1,
                acceptedHardwareParityRecordCount: 1,
                hardwareEvidenceReportHashes: ["hardware-report-hash-a"],
                hardwareEvidenceMeasurementSystems: ["bench-measurement"],
                hardwareEvidenceDeviceIDs: ["measurement-device-a"],
                hardwareJointCalibrationRecordCount: 1,
                hardwareJointSampleCount: 3,
                measuredHardwareJointSampleCount: 0,
                observedHardwareJointSampleCount: 0,
                path: "physics/descriptor-corpus-acceptance.json"
            ),
        ]
    )

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError
        .missingPhysicsCorpusHardwareParityEvidence("reference-physics-corpus")) {
        try TrainingProjectEvidencePackValidator().validate(pack)
    }
}

@Test func trainingProjectEvidencePackValidatorRejectsImpossibleHardwareJointCorpusCounts() throws {
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        physicsCorpora: [
            TrainingProjectEvidencePack.PhysicsCorpusEvidence(
                corpusID: "reference-physics-corpus",
                acceptedRecordCount: 1,
                hardwareParityGapCount: 0,
                requiredReadinessLevels: [.hardwareParity],
                hardwareEvidenceRecordCount: 1,
                acceptedHardwareParityRecordCount: 1,
                hardwareEvidenceReportHashes: ["hardware-report-hash-a"],
                hardwareEvidenceMeasurementSystems: ["bench-measurement"],
                hardwareEvidenceDeviceIDs: ["measurement-device-a"],
                hardwareJointCalibrationRecordCount: 1,
                hardwareJointSampleCount: 2,
                measuredHardwareJointSampleCount: 3,
                observedHardwareJointSampleCount: 2,
                path: "physics/descriptor-corpus-acceptance.json"
            ),
        ]
    )

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError
        .invalidPhysicsCorpusMeasuredHardwareJointSampleCount(
            corpusID: "reference-physics-corpus",
            measuredHardwareJointSampleCount: 3
        )) {
        try TrainingProjectEvidencePackValidator().validate(pack)
    }
}

@Test func trainingProjectEvidencePackValidatorRejectsImpossibleHardwareSensorCorpusCounts() throws {
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        physicsCorpora: [
            TrainingProjectEvidencePack.PhysicsCorpusEvidence(
                corpusID: "reference-physics-corpus",
                acceptedRecordCount: 1,
                hardwareParityGapCount: 0,
                requiredReadinessLevels: [.hardwareParity],
                hardwareEvidenceRecordCount: 1,
                acceptedHardwareParityRecordCount: 1,
                hardwareEvidenceReportHashes: ["hardware-report-hash-a"],
                hardwareEvidenceMeasurementSystems: ["bench-measurement"],
                hardwareEvidenceDeviceIDs: ["measurement-device-a"],
                hardwareSensorCalibrationRecordCount: 1,
                hardwareSensorSampleCount: 2,
                observedHardwareSensorSampleCount: 3,
                path: "physics/descriptor-corpus-acceptance.json"
            ),
        ]
    )

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError
        .invalidPhysicsCorpusObservedHardwareSensorSampleCount(
            corpusID: "reference-physics-corpus",
            observedHardwareSensorSampleCount: 3
        )) {
        try TrainingProjectEvidencePackValidator().validate(pack)
    }
}

@Test func trainingProjectEvidencePackValidatorRejectsImpossibleContactReplayCorpusCounts() throws {
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        physicsCorpora: [
            TrainingProjectEvidencePack.PhysicsCorpusEvidence(
                corpusID: "reference-physics-corpus",
                acceptedRecordCount: 1,
                hardwareParityGapCount: 0,
                requiredReadinessLevels: [.contactTraining],
                contactReplayRecordCount: 2,
                path: "physics/descriptor-corpus-acceptance.json"
            ),
        ]
    )

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError
        .invalidPhysicsCorpusContactReplayRecordCount(
            corpusID: "reference-physics-corpus",
            contactReplayRecordCount: 2
        )) {
        try TrainingProjectEvidencePackValidator().validate(pack)
    }
}

@Test func trainingProjectEvidencePackValidatorRejectsContactTrainingReadinessWithoutReplayEvidence() throws {
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        physicsCorpora: [
            TrainingProjectEvidencePack.PhysicsCorpusEvidence(
                corpusID: "reference-physics-corpus",
                acceptedRecordCount: 1,
                hardwareParityGapCount: 0,
                requiredReadinessLevels: [.contactTraining],
                contactReplayRecordCount: 0,
                path: "physics/descriptor-corpus-acceptance.json"
            ),
        ]
    )

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError
        .missingPhysicsCorpusContactReplayEvidence("reference-physics-corpus")) {
        try TrainingProjectEvidencePackValidator().validate(pack)
    }
}

@Test func trainingProjectEvidencePackStoreRejectsPhysicsCorpusSymlinkEscape() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    let externalDirectory = try projectEvidenceTemporaryDirectory()
    defer {
        projectEvidenceCleanup(directory)
        projectEvidenceCleanup(externalDirectory)
    }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let summary = projectEvidenceDescriptorCorpusSummary()
    let physicsPath = "physics/descriptor-corpus-acceptance.json"
    let linkURL = directory.appendingPathComponent(physicsPath)
    let externalPhysicsURL = externalDirectory.appendingPathComponent("descriptor-corpus-acceptance.json")
    try projectEvidenceWriteJSON(summary, to: externalPhysicsURL)
    try FileManager.default.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: externalPhysicsURL)
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        physicsCorpora: [TrainingProjectEvidencePack.PhysicsCorpusEvidence(
            summary: summary,
            path: physicsPath
        )]
    )

    #expect(throws: TrainingProjectEvidencePackArtifactStore.StoreError
        .referencedPhysicsCorpusAcceptanceEscapesRoot(physicsPath)) {
        _ = try TrainingProjectEvidencePackArtifactStore().write(pack, to: directory)
    }
}

@Test func trainingProjectEvidencePackStoreRejectsPhysicsCorpusDirectorySymlinkEscape() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    let externalDirectory = try projectEvidenceTemporaryDirectory()
    defer {
        projectEvidenceCleanup(directory)
        projectEvidenceCleanup(externalDirectory)
    }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let summary = projectEvidenceDescriptorCorpusSummary()
    let physicsPath = "physics/descriptor-corpus-acceptance.json"
    let externalPhysicsURL = externalDirectory.appendingPathComponent(
        "descriptor-corpus-acceptance.json",
        isDirectory: false
    )
    try projectEvidenceWriteJSON(summary, to: externalPhysicsURL)
    let symlinkDirectory = directory.appendingPathComponent("physics", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: symlinkDirectory, withDestinationURL: externalDirectory)
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        physicsCorpora: [TrainingProjectEvidencePack.PhysicsCorpusEvidence(
            summary: summary,
            path: physicsPath
        )]
    )

    #expect(throws: TrainingProjectEvidencePackArtifactStore.StoreError
        .referencedPhysicsCorpusAcceptanceEscapesRoot(physicsPath)) {
        _ = try TrainingProjectEvidencePackArtifactStore().write(pack, to: directory)
    }
}

@Test func trainingProjectEvidencePackValidatorRejectsEscapingPhysicsCorpusPath() throws {
    let summary = projectEvidenceDescriptorCorpusSummary()
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        physicsCorpora: [
            TrainingProjectEvidencePack.PhysicsCorpusEvidence(
                summary: summary,
                path: "../descriptor-corpus-acceptance.json"
            ),
        ]
    )

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError.escapingPhysicsCorpusPath(
        "../descriptor-corpus-acceptance.json"
    )) {
        try TrainingProjectEvidencePackValidator().validate(pack)
    }
}

@Test func consciousUnconsciousObservabilityArtifactValidatorAcceptsCompleteArtifact() throws {
    let artifact = projectEvidenceObservabilityArtifact()

    try ConsciousUnconsciousObservabilityArtifactValidator().validate(artifact)

    #expect(artifact.upwardSummaries[0].channels.map(\.name).contains("constraintPressure"))
    #expect(artifact.latencyBudgetViolations[0].observedMilliseconds > artifact.latencyBudgetViolations[0].budgetMilliseconds)
}

@Test func consciousUnconsciousObservabilityArtifactValidatorRejectsMissingUpwardSummaryChannel() throws {
    let artifact = ConsciousUnconsciousObservabilityArtifact(
        runID: "run-a",
        scenarioID: "scenario-1",
        seed: 1,
        timeStep: 0.001,
        descendingSnapshots: [
            projectEvidenceDescendingSnapshot(),
        ],
        upwardSummaries: [
            ConsciousUnconsciousObservabilityArtifact.UpwardSummary(
                stepIndex: 0,
                timestamp: 0,
                channels: projectEvidenceSummaryChannels().filter { $0.name != "risk" }
            ),
        ],
        arbitrationDecisions: [
            projectEvidenceArbitrationDecision(),
        ]
    )

    #expect(throws: ConsciousUnconsciousObservabilityArtifactValidator.ValidationError
        .missingSummaryChannel(stepIndex: 0, name: "risk")) {
        try ConsciousUnconsciousObservabilityArtifactValidator().validate(artifact)
    }
}

@Test func consciousUnconsciousObservabilityArtifactValidatorRejectsLatencyRecordWithinBudget() throws {
    let artifact = ConsciousUnconsciousObservabilityArtifact(
        runID: "run-a",
        scenarioID: "scenario-1",
        seed: 1,
        timeStep: 0.001,
        descendingSnapshots: [
            projectEvidenceDescendingSnapshot(),
        ],
        upwardSummaries: [
            projectEvidenceUpwardSummary(),
        ],
        arbitrationDecisions: [
            projectEvidenceArbitrationDecision(),
        ],
        latencyBudgetViolations: [
            ConsciousUnconsciousObservabilityArtifact.LatencyBudgetViolation(
                stepIndex: 0,
                timestamp: 0,
                path: "summaryExport",
                budgetMilliseconds: 2,
                observedMilliseconds: 2,
                reason: "equal-to-budget"
            ),
        ]
    )

    #expect(throws: ConsciousUnconsciousObservabilityArtifactValidator.ValidationError
        .latencyBudgetNotExceeded(stepIndex: 0, budget: 2, observed: 2)) {
        try ConsciousUnconsciousObservabilityArtifactValidator().validate(artifact)
    }
}

@Test func consciousUnconsciousObservabilityArtifactValidatorRejectsMisalignedUpwardTimeline() throws {
    let artifact = ConsciousUnconsciousObservabilityArtifact(
        runID: "run-a",
        scenarioID: "scenario-1",
        seed: 1,
        timeStep: 0.001,
        descendingSnapshots: [
            projectEvidenceDescendingSnapshot(),
        ],
        upwardSummaries: [
            ConsciousUnconsciousObservabilityArtifact.UpwardSummary(
                stepIndex: 1,
                timestamp: 0,
                channels: projectEvidenceSummaryChannels()
            ),
        ],
        arbitrationDecisions: [
            projectEvidenceArbitrationDecision(),
        ]
    )

    #expect(throws: ConsciousUnconsciousObservabilityArtifactValidator.ValidationError
        .timelinePointMismatch(
            kind: "upwardSummary",
            index: 0,
            expectedStepIndex: 0,
            actualStepIndex: 1,
            expectedTimestamp: 0,
            actualTimestamp: 0
        )) {
        try ConsciousUnconsciousObservabilityArtifactValidator().validate(artifact)
    }
}

@Test func consciousUnconsciousObservabilityArtifactValidatorRejectsRepeatedAnchorTimelinePoint() throws {
    let artifact = ConsciousUnconsciousObservabilityArtifact(
        runID: "run-a",
        scenarioID: "scenario-1",
        seed: 1,
        timeStep: 0.001,
        descendingSnapshots: [
            projectEvidenceDescendingSnapshot(),
            ConsciousUnconsciousObservabilityArtifact.DescendingSnapshot(
                stepIndex: 0,
                timestamp: 0.001,
                source: "planner",
                goalID: "goal-a",
                priority: 0.7,
                inhibition: 0.1,
                contextHash: "context-b"
            ),
        ],
        upwardSummaries: [
            projectEvidenceUpwardSummary(),
            ConsciousUnconsciousObservabilityArtifact.UpwardSummary(
                stepIndex: 0,
                timestamp: 0.001,
                channels: projectEvidenceSummaryChannels()
            ),
        ],
        arbitrationDecisions: [
            projectEvidenceArbitrationDecision(),
            ConsciousUnconsciousObservabilityArtifact.ArbitrationDecision(
                stepIndex: 0,
                timestamp: 0.001,
                coreDriveMagnitude: 0.6,
                reflexCorrectionMagnitude: 0.1,
                finalDriveMagnitude: 0.5,
                reflexPreemptedDescendingBias: false,
                reason: "repeated anchor step"
            ),
        ]
    )

    #expect(throws: ConsciousUnconsciousObservabilityArtifactValidator.ValidationError
        .nonIncreasingTimelinePoint(
            kind: "descending",
            index: 1,
            previousStepIndex: 0,
            currentStepIndex: 0,
            previousTimestamp: 0,
            currentTimestamp: 0.001
        )) {
        try ConsciousUnconsciousObservabilityArtifactValidator().validate(artifact)
    }
}

@Test func consciousUnconsciousObservabilityArtifactValidatorRejectsLatencyOutsideTimeline() throws {
    let artifact = ConsciousUnconsciousObservabilityArtifact(
        runID: "run-a",
        scenarioID: "scenario-1",
        seed: 1,
        timeStep: 0.001,
        descendingSnapshots: [
            projectEvidenceDescendingSnapshot(),
        ],
        upwardSummaries: [
            projectEvidenceUpwardSummary(),
        ],
        arbitrationDecisions: [
            projectEvidenceArbitrationDecision(),
        ],
        latencyBudgetViolations: [
            ConsciousUnconsciousObservabilityArtifact.LatencyBudgetViolation(
                stepIndex: 1,
                timestamp: 0.001,
                path: "summaryExport",
                budgetMilliseconds: 2,
                observedMilliseconds: 3,
                reason: "orphan latency event"
            ),
        ]
    )

    #expect(throws: ConsciousUnconsciousObservabilityArtifactValidator.ValidationError
        .latencyTimelinePointMissing(stepIndex: 1, timestamp: 0.001)) {
        try ConsciousUnconsciousObservabilityArtifactValidator().validate(artifact)
    }
}

@Test func trainingProjectEvidencePackStoreWritesAndReloadsObservabilityEvidence() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    defer { projectEvidenceCleanup(directory) }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let artifact = projectEvidenceObservabilityArtifact()
    let observabilityPath = "observability/conscious-unconscious-observability.json"
    _ = try ConsciousUnconsciousObservabilityArtifactStore().write(
        artifact,
        to: directory.appendingPathComponent(observabilityPath)
    )
    let observabilityEvidence = TrainingProjectEvidencePack.ObservabilityArtifactEvidence(
        artifact: artifact,
        path: observabilityPath
    )

    let loaded = try TrainingProjectEvidencePackArtifactStore().writeValidatedPack(
        projectID: "reference-foundation",
        datasetMetadata: [projectEvidenceMetadata(id: "episode-a")],
        curriculum: projectEvidenceCurriculum(),
        checkpointDecision: projectEvidenceAcceptedCheckpointDecision(),
        regressionArtifacts: [projectEvidenceRegressionArtifact()],
        observabilityArtifacts: [observabilityEvidence],
        to: directory,
        createdAt: Date(timeIntervalSince1970: 100)
    )

    #expect(loaded.observabilityArtifacts == [observabilityEvidence])
    #expect(loaded.observabilityArtifacts.first?.upwardSummaryCount == 1)
}

@Test func trainingProjectEvidencePackStoreRejectsMismatchedObservabilityEvidence() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    defer { projectEvidenceCleanup(directory) }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let expectedArtifact = projectEvidenceObservabilityArtifact(runID: "run-a")
    let replacementArtifact = projectEvidenceObservabilityArtifact(runID: "run-b")
    let observabilityPath = "observability/conscious-unconscious-observability.json"
    _ = try ConsciousUnconsciousObservabilityArtifactStore().write(
        replacementArtifact,
        to: directory.appendingPathComponent(observabilityPath)
    )
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        observabilityArtifacts: [
            TrainingProjectEvidencePack.ObservabilityArtifactEvidence(
                artifact: expectedArtifact,
                path: observabilityPath
            ),
        ]
    )

    #expect(throws: TrainingProjectEvidencePackArtifactStore.StoreError
        .referencedObservabilityArtifactMismatch(observabilityPath)) {
        _ = try TrainingProjectEvidencePackArtifactStore().write(pack, to: directory)
    }
}

@Test func trainingProjectEvidencePackStoreRejectsObservabilitySymlinkEscape() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    let externalDirectory = try projectEvidenceTemporaryDirectory()
    defer {
        projectEvidenceCleanup(directory)
        projectEvidenceCleanup(externalDirectory)
    }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let artifact = projectEvidenceObservabilityArtifact()
    let observabilityPath = "observability/conscious-unconscious-observability.json"
    let linkURL = directory.appendingPathComponent(observabilityPath)
    let externalURL = externalDirectory.appendingPathComponent("conscious-unconscious-observability.json")
    _ = try ConsciousUnconsciousObservabilityArtifactStore().write(artifact, to: externalURL)
    try FileManager.default.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: externalURL)
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        observabilityArtifacts: [
            TrainingProjectEvidencePack.ObservabilityArtifactEvidence(
                artifact: artifact,
                path: observabilityPath
            ),
        ]
    )

    #expect(throws: TrainingProjectEvidencePackArtifactStore.StoreError
        .referencedObservabilityArtifactEscapesRoot(observabilityPath)) {
        _ = try TrainingProjectEvidencePackArtifactStore().write(pack, to: directory)
    }
}

@Test func trainingProjectEvidencePackStoreRejectsObservabilityDirectorySymlinkEscape() throws {
    let directory = try projectEvidenceTemporaryDirectory()
    let externalDirectory = try projectEvidenceTemporaryDirectory()
    defer {
        projectEvidenceCleanup(directory)
        projectEvidenceCleanup(externalDirectory)
    }
    try projectEvidenceCreateFile(
        at: directory.appendingPathComponent("evaluations/final/checkpoint-evaluation.json")
    )
    let artifact = projectEvidenceObservabilityArtifact()
    let observabilityPath = "observability/conscious-unconscious-observability.json"
    let externalURL = externalDirectory.appendingPathComponent("conscious-unconscious-observability.json")
    _ = try ConsciousUnconsciousObservabilityArtifactStore().write(artifact, to: externalURL)
    try FileManager.default.createSymbolicLink(
        at: directory.appendingPathComponent("observability", isDirectory: true),
        withDestinationURL: externalDirectory
    )
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        observabilityArtifacts: [
            TrainingProjectEvidencePack.ObservabilityArtifactEvidence(
                artifact: artifact,
                path: observabilityPath
            ),
        ]
    )

    #expect(throws: TrainingProjectEvidencePackArtifactStore.StoreError
        .referencedObservabilityArtifactEscapesRoot(observabilityPath)) {
        _ = try TrainingProjectEvidencePackArtifactStore().write(pack, to: directory)
    }
}

@Test func trainingProjectEvidencePackValidatorRejectsUnmetStressCoverageEvidence() throws {
    let stressEvidence = TrainingProjectEvidencePack.StressSuiteEvidence(
        suiteID: "reference-attitude-stress",
        profile: .referenceQuadrotor,
        recordCount: 1,
        coverageTargets: [
            TrainingProjectEvidencePack.StressCoverageTargetEvidence(
                dimension: .longHorizon,
                minimumCount: 2,
                actualCount: 1
            ),
        ],
        replayStatus: .performed,
        replayCheckCount: 1,
        path: "stress/reference-attitude-stress.json"
    )
    let pack = projectEvidencePack(
        projectID: "reference-foundation",
        stressSuites: [stressEvidence]
    )

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError.stressCoverageTargetNotMet(
        suiteID: "reference-attitude-stress",
        dimension: .longHorizon,
        minimumCount: 2,
        actualCount: 1
    )) {
        try TrainingProjectEvidencePackValidator().validate(pack)
    }
}

@Test func trainingProjectEvidencePackValidatorAcceptsRequiredReferenceM2StressCoverage() throws {
    let validator = TrainingProjectEvidencePackValidator()
    let stressEvidence = TrainingProjectEvidencePack.StressSuiteEvidence(
        manifest: try projectEvidenceM2StressManifest(),
        path: "stress/reference-m2-stress.json"
    )

    let pack = try validator.makePack(
        projectID: "reference-foundation",
        datasetMetadata: [projectEvidenceMetadata(id: "episode-a")],
        curriculum: projectEvidenceCurriculum(),
        checkpointDecision: projectEvidenceAcceptedCheckpointDecision(),
        regressionArtifacts: [projectEvidenceRegressionArtifact()],
        stressSuites: [stressEvidence],
        requiresReferenceM2StressCoverage: true
    )

    #expect(validator.referenceM2StressCoverageComplete(in: pack))
    #expect(pack.stressSuites.first?.referenceM2BenchmarkEvidence?.isComplete == true)
    #expect(pack.stressSuites.first?.referenceM2BenchmarkEvidence?.plannerDegradationScenarioIDs == ["LH-TASK-0"])
}

@Test func trainingProjectEvidencePackValidatorRejectsDimensionOnlyReferenceM2StressCoverageWhenRequired() throws {
    let validator = TrainingProjectEvidencePackValidator()
    let stressEvidence = TrainingProjectEvidencePack.StressSuiteEvidence(
        suiteID: "reference-m2-dimension-only",
        profile: .referenceQuadrotor,
        recordCount: 3,
        coverageTargets: StressSuiteManifest.requiredReferenceQuadrotorM2Dimensions.map {
            TrainingProjectEvidencePack.StressCoverageTargetEvidence(
                dimension: $0,
                minimumCount: 1,
                actualCount: 1
            )
        },
        replayStatus: .performed,
        replayCheckCount: 3,
        path: "stress/reference-m2-dimension-only.json"
    )

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError.missingReferenceM2SemanticEvidence([
        "reference-m2-dimension-only",
    ])) {
        _ = try validator.makePack(
            projectID: "reference-foundation",
            datasetMetadata: [projectEvidenceMetadata(id: "episode-a")],
            curriculum: projectEvidenceCurriculum(),
            checkpointDecision: projectEvidenceAcceptedCheckpointDecision(),
            regressionArtifacts: [projectEvidenceRegressionArtifact()],
            stressSuites: [stressEvidence],
            requiresReferenceM2StressCoverage: true
        )
    }
}

@Test func trainingProjectEvidencePackValidatorRejectsMissingReferenceM2StressCoverageWhenRequired() throws {
    let validator = TrainingProjectEvidencePackValidator()
    let stressEvidence = TrainingProjectEvidencePack.StressSuiteEvidence(
        manifest: try projectEvidenceStressManifest(),
        path: "stress/reference-attitude-stress.json"
    )

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError.missingReferenceM2StressCoverage([
        .plannerDegradation,
        .morphologyTransfer,
        .torqueDisturbance,
        .partialObservability,
    ])) {
        _ = try validator.makePack(
            projectID: "reference-foundation",
            datasetMetadata: [projectEvidenceMetadata(id: "episode-a")],
            curriculum: projectEvidenceCurriculum(),
            checkpointDecision: projectEvidenceAcceptedCheckpointDecision(),
            regressionArtifacts: [projectEvidenceRegressionArtifact()],
            stressSuites: [stressEvidence],
            requiresReferenceM2StressCoverage: true
        )
    }
}

@Test func trainingProjectEvidencePackComparatorPrefersAcceptedCandidateOverStagedIncumbent() throws {
    let incumbent = projectEvidencePack(
        projectID: "incumbent",
        checkpoint: projectEvidenceStagedCheckpointDecision(),
        createdAt: Date(timeIntervalSince1970: 200)
    )
    let candidate = projectEvidencePack(
        projectID: "candidate",
        checkpoint: projectEvidenceAcceptedCheckpointDecision(),
        createdAt: Date(timeIntervalSince1970: 100)
    )

    let comparison = try TrainingProjectEvidencePackComparator().compare(
        incumbent: incumbent,
        candidate: candidate
    )

    #expect(comparison.decision == .preferCandidate)
    #expect(comparison.dominantFactor == .checkpointState)
    #expect(comparison.incumbentScore.checkpointState == .staged)
    #expect(comparison.candidateScore.checkpointState == .accepted)
}

@Test func trainingProjectEvidencePackComparatorKeepsIncumbentWithMoreAcceptedRegressionEvidence() throws {
    let incumbent = projectEvidencePack(
        projectID: "incumbent",
        regressionArtifacts: [
            projectEvidenceRegressionArtifact(path: "evaluations/final/checkpoint-evaluation.json", accepted: true),
            projectEvidenceRegressionArtifact(path: "stress/reference-attitude.json", accepted: true),
        ],
        createdAt: Date(timeIntervalSince1970: 100)
    )
    let candidate = projectEvidencePack(
        projectID: "candidate",
        datasets: [projectEvidenceMetadata(id: "episode-a", recordCount: 256)],
        regressionArtifacts: [
            projectEvidenceRegressionArtifact(path: "evaluations/final/checkpoint-evaluation.json", accepted: true),
            projectEvidenceRegressionArtifact(path: "stress/reference-attitude.json", accepted: false),
        ],
        createdAt: Date(timeIntervalSince1970: 200)
    )

    let comparison = try TrainingProjectEvidencePackComparator().compare(
        incumbent: incumbent,
        candidate: candidate
    )

    #expect(comparison.decision == .keepIncumbent)
    #expect(comparison.dominantFactor == .acceptedRegressionArtifacts)
    #expect(comparison.incumbentScore.acceptedRegressionArtifactCount == 2)
    #expect(comparison.candidateScore.acceptedRegressionArtifactCount == 1)
}

@Test func trainingProjectEvidencePackComparatorPrefersCandidateWithStressEvidence() throws {
    let stressEvidence = TrainingProjectEvidencePack.StressSuiteEvidence(
        manifest: try projectEvidenceStressManifest(),
        path: "stress/reference-attitude-stress.json"
    )
    let incumbent = projectEvidencePack(projectID: "incumbent")
    let candidate = projectEvidencePack(
        projectID: "candidate",
        stressSuites: [stressEvidence]
    )

    let comparison = try TrainingProjectEvidencePackComparator().compare(
        incumbent: incumbent,
        candidate: candidate
    )

    #expect(comparison.decision == .preferCandidate)
    #expect(comparison.dominantFactor == .stressSuites)
    #expect(comparison.candidateScore.stressScenarioRecordCount == 1)
}

@Test func trainingProjectEvidencePackComparatorPrefersCandidateWithPhysicsCorpusEvidence() throws {
    let physicsEvidence = TrainingProjectEvidencePack.PhysicsCorpusEvidence(
        summary: projectEvidenceDescriptorCorpusSummary(),
        path: "physics/descriptor-corpus-acceptance.json"
    )
    let incumbent = projectEvidencePack(projectID: "incumbent")
    let candidate = projectEvidencePack(
        projectID: "candidate",
        physicsCorpora: [physicsEvidence]
    )

    let comparison = try TrainingProjectEvidencePackComparator().compare(
        incumbent: incumbent,
        candidate: candidate
    )

    #expect(comparison.decision == .preferCandidate)
    #expect(comparison.dominantFactor == .physicsCorpora)
    #expect(comparison.candidateScore.physicsCorpusAcceptedRecordCount == 1)
}

@Test func trainingProjectEvidencePackComparatorPrefersHardwareBackedPhysicsCorpusEvidence() throws {
    let incumbentPhysicsEvidence = TrainingProjectEvidencePack.PhysicsCorpusEvidence(
        summary: projectEvidenceDescriptorCorpusSummary(),
        path: "physics/incumbent-descriptor-corpus-acceptance.json"
    )
    let candidatePhysicsEvidence = TrainingProjectEvidencePack.PhysicsCorpusEvidence(
        summary: projectEvidenceDescriptorCorpusSummary(
            requiredReadiness: .hardwareParity,
            hardwareParity: .accepted,
            hardwareEvidence: projectEvidenceHardwareEvidence(reportHash: "hardware-report-hash-a")
        ),
        path: "physics/candidate-descriptor-corpus-acceptance.json"
    )
    let incumbent = projectEvidencePack(
        projectID: "incumbent",
        physicsCorpora: [incumbentPhysicsEvidence],
        createdAt: Date(timeIntervalSince1970: 200)
    )
    let candidate = projectEvidencePack(
        projectID: "candidate",
        physicsCorpora: [candidatePhysicsEvidence],
        createdAt: Date(timeIntervalSince1970: 100)
    )

    let comparison = try TrainingProjectEvidencePackComparator().compare(
        incumbent: incumbent,
        candidate: candidate
    )

    #expect(comparison.decision == .preferCandidate)
    #expect(comparison.dominantFactor == .physicsCorpusAcceptedHardwareParity)
    #expect(comparison.incumbentScore.physicsCorpusAcceptedRecordCount == 1)
    #expect(comparison.candidateScore.physicsCorpusAcceptedRecordCount == 1)
    #expect(comparison.incumbentScore.physicsCorpusAcceptedHardwareParityRecordCount == 0)
    #expect(comparison.candidateScore.physicsCorpusAcceptedHardwareParityRecordCount == 1)
    #expect(comparison.candidateScore.physicsCorpusHardwareEvidenceRecordCount == 1)
    #expect(comparison.candidateScore.physicsCorpusHardwareReportHashCount == 1)
}

@Test func trainingProjectEvidencePackComparatorPrefersDistinctHardwareReportProvenance() throws {
    let incumbentPhysicsEvidence = [
        TrainingProjectEvidencePack.PhysicsCorpusEvidence(
            summary: projectEvidenceDescriptorCorpusSummary(
                corpusID: "incumbent-physics-corpus-a",
                entryID: "incumbent-physics-entry-a",
                requiredReadiness: .hardwareParity,
                hardwareParity: .accepted,
                hardwareEvidence: projectEvidenceHardwareEvidence(reportHash: "hardware-report-hash-a")
            ),
            path: "physics/incumbent-a/descriptor-corpus-acceptance.json"
        ),
        TrainingProjectEvidencePack.PhysicsCorpusEvidence(
            summary: projectEvidenceDescriptorCorpusSummary(
                corpusID: "incumbent-physics-corpus-b",
                entryID: "incumbent-physics-entry-b",
                requiredReadiness: .hardwareParity,
                hardwareParity: .accepted,
                hardwareEvidence: projectEvidenceHardwareEvidence(reportHash: "hardware-report-hash-a")
            ),
            path: "physics/incumbent-b/descriptor-corpus-acceptance.json"
        ),
    ]
    let candidatePhysicsEvidence = [
        TrainingProjectEvidencePack.PhysicsCorpusEvidence(
            summary: projectEvidenceDescriptorCorpusSummary(
                corpusID: "candidate-physics-corpus-a",
                entryID: "candidate-physics-entry-a",
                requiredReadiness: .hardwareParity,
                hardwareParity: .accepted,
                hardwareEvidence: projectEvidenceHardwareEvidence(reportHash: "hardware-report-hash-a")
            ),
            path: "physics/candidate-a/descriptor-corpus-acceptance.json"
        ),
        TrainingProjectEvidencePack.PhysicsCorpusEvidence(
            summary: projectEvidenceDescriptorCorpusSummary(
                corpusID: "candidate-physics-corpus-b",
                entryID: "candidate-physics-entry-b",
                requiredReadiness: .hardwareParity,
                hardwareParity: .accepted,
                hardwareEvidence: projectEvidenceHardwareEvidence(reportHash: "hardware-report-hash-b")
            ),
            path: "physics/candidate-b/descriptor-corpus-acceptance.json"
        ),
    ]
    let incumbent = projectEvidencePack(
        projectID: "incumbent",
        physicsCorpora: incumbentPhysicsEvidence,
        createdAt: Date(timeIntervalSince1970: 200)
    )
    let candidate = projectEvidencePack(
        projectID: "candidate",
        physicsCorpora: candidatePhysicsEvidence,
        createdAt: Date(timeIntervalSince1970: 100)
    )

    let comparison = try TrainingProjectEvidencePackComparator().compare(
        incumbent: incumbent,
        candidate: candidate
    )

    #expect(comparison.decision == .preferCandidate)
    #expect(comparison.dominantFactor == .physicsCorpusHardwareReports)
    #expect(comparison.incumbentScore.physicsCorpusHardwareEvidenceRecordCount == 2)
    #expect(comparison.candidateScore.physicsCorpusHardwareEvidenceRecordCount == 2)
    #expect(comparison.incumbentScore.physicsCorpusHardwareReportHashCount == 1)
    #expect(comparison.candidateScore.physicsCorpusHardwareReportHashCount == 2)
}

@Test func trainingProjectEvidencePackComparatorPrefersDistinctMeasurementDeviceProvenance() throws {
    let incumbentPhysicsEvidence = [
        TrainingProjectEvidencePack.PhysicsCorpusEvidence(
            summary: projectEvidenceDescriptorCorpusSummary(
                corpusID: "incumbent-physics-corpus-a",
                entryID: "incumbent-physics-entry-a",
                requiredReadiness: .hardwareParity,
                hardwareParity: .accepted,
                hardwareEvidence: projectEvidenceHardwareEvidence(
                    reportHash: "hardware-report-hash-a",
                    deviceID: "measurement-device-a"
                )
            ),
            path: "physics/incumbent-a/descriptor-corpus-acceptance.json"
        ),
        TrainingProjectEvidencePack.PhysicsCorpusEvidence(
            summary: projectEvidenceDescriptorCorpusSummary(
                corpusID: "incumbent-physics-corpus-b",
                entryID: "incumbent-physics-entry-b",
                requiredReadiness: .hardwareParity,
                hardwareParity: .accepted,
                hardwareEvidence: projectEvidenceHardwareEvidence(
                    reportHash: "hardware-report-hash-a",
                    deviceID: "measurement-device-a"
                )
            ),
            path: "physics/incumbent-b/descriptor-corpus-acceptance.json"
        ),
    ]
    let candidatePhysicsEvidence = [
        TrainingProjectEvidencePack.PhysicsCorpusEvidence(
            summary: projectEvidenceDescriptorCorpusSummary(
                corpusID: "candidate-physics-corpus-a",
                entryID: "candidate-physics-entry-a",
                requiredReadiness: .hardwareParity,
                hardwareParity: .accepted,
                hardwareEvidence: projectEvidenceHardwareEvidence(
                    reportHash: "hardware-report-hash-a",
                    deviceID: "measurement-device-a"
                )
            ),
            path: "physics/candidate-a/descriptor-corpus-acceptance.json"
        ),
        TrainingProjectEvidencePack.PhysicsCorpusEvidence(
            summary: projectEvidenceDescriptorCorpusSummary(
                corpusID: "candidate-physics-corpus-b",
                entryID: "candidate-physics-entry-b",
                requiredReadiness: .hardwareParity,
                hardwareParity: .accepted,
                hardwareEvidence: projectEvidenceHardwareEvidence(
                    reportHash: "hardware-report-hash-a",
                    deviceID: "measurement-device-b"
                )
            ),
            path: "physics/candidate-b/descriptor-corpus-acceptance.json"
        ),
    ]
    let incumbent = projectEvidencePack(
        projectID: "incumbent",
        physicsCorpora: incumbentPhysicsEvidence,
        createdAt: Date(timeIntervalSince1970: 200)
    )
    let candidate = projectEvidencePack(
        projectID: "candidate",
        physicsCorpora: candidatePhysicsEvidence,
        createdAt: Date(timeIntervalSince1970: 100)
    )

    let comparison = try TrainingProjectEvidencePackComparator().compare(
        incumbent: incumbent,
        candidate: candidate
    )

    #expect(comparison.decision == .preferCandidate)
    #expect(comparison.dominantFactor == .physicsCorpusMeasurementDevices)
    #expect(comparison.incumbentScore.physicsCorpusHardwareEvidenceRecordCount == 2)
    #expect(comparison.candidateScore.physicsCorpusHardwareEvidenceRecordCount == 2)
    #expect(comparison.incumbentScore.physicsCorpusHardwareMeasurementSystemCount == 1)
    #expect(comparison.candidateScore.physicsCorpusHardwareMeasurementSystemCount == 1)
    #expect(comparison.incumbentScore.physicsCorpusHardwareMeasurementDeviceIDCount == 1)
    #expect(comparison.candidateScore.physicsCorpusHardwareMeasurementDeviceIDCount == 2)
    #expect(comparison.incumbentScore.physicsCorpusHardwareReportHashCount == 1)
    #expect(comparison.candidateScore.physicsCorpusHardwareReportHashCount == 1)
}

@Test func trainingProjectEvidencePackComparatorPrefersJointCalibratedHardwareCorpusEvidence() throws {
    let incumbentPhysicsEvidence = TrainingProjectEvidencePack.PhysicsCorpusEvidence(
        summary: projectEvidenceDescriptorCorpusSummary(
            requiredReadiness: .hardwareParity,
            hardwareParity: .accepted,
            hardwareEvidence: projectEvidenceHardwareEvidence(reportHash: "hardware-report-hash-a")
        ),
        path: "physics/incumbent-descriptor-corpus-acceptance.json"
    )
    let candidatePhysicsEvidence = TrainingProjectEvidencePack.PhysicsCorpusEvidence(
        summary: projectEvidenceDescriptorCorpusSummary(
            requiredReadiness: .hardwareParity,
            hardwareParity: .accepted,
            hardwareEvidence: projectEvidenceHardwareEvidence(
                reportHash: "hardware-report-hash-a",
                jointSampleCount: 6,
                measuredJointSampleCount: 6,
                observedJointSampleCount: 6
            )
        ),
        path: "physics/candidate-descriptor-corpus-acceptance.json"
    )
    let incumbent = projectEvidencePack(
        projectID: "incumbent",
        physicsCorpora: [incumbentPhysicsEvidence],
        createdAt: Date(timeIntervalSince1970: 200)
    )
    let candidate = projectEvidencePack(
        projectID: "candidate",
        physicsCorpora: [candidatePhysicsEvidence],
        createdAt: Date(timeIntervalSince1970: 100)
    )

    let comparison = try TrainingProjectEvidencePackComparator().compare(
        incumbent: incumbent,
        candidate: candidate
    )

    #expect(comparison.decision == .preferCandidate)
    #expect(comparison.dominantFactor == .physicsCorpusJointCoverage)
    #expect(comparison.incumbentScore.physicsCorpusObservedHardwareJointSampleCount == 3)
    #expect(comparison.candidateScore.physicsCorpusObservedHardwareJointSampleCount == 6)
}

@Test func trainingProjectEvidencePackComparatorPrefersSensorCalibratedHardwareCorpusEvidence() throws {
    let incumbentPhysicsEvidence = TrainingProjectEvidencePack.PhysicsCorpusEvidence(
        summary: projectEvidenceDescriptorCorpusSummary(
            requiredReadiness: .hardwareParity,
            hardwareParity: .accepted,
            hardwareEvidence: projectEvidenceHardwareEvidence(reportHash: "hardware-report-hash-a")
        ),
        path: "physics/incumbent-descriptor-corpus-acceptance.json"
    )
    let candidatePhysicsEvidence = TrainingProjectEvidencePack.PhysicsCorpusEvidence(
        summary: projectEvidenceDescriptorCorpusSummary(
            requiredReadiness: .hardwareParity,
            hardwareParity: .accepted,
            hardwareEvidence: projectEvidenceHardwareEvidence(
                reportHash: "hardware-report-hash-a",
                sensorCalibrationCount: 1,
                sensorSampleCount: 3,
                observedSensorSampleCount: 3
            )
        ),
        path: "physics/candidate-descriptor-corpus-acceptance.json"
    )
    let incumbent = projectEvidencePack(
        projectID: "incumbent",
        physicsCorpora: [incumbentPhysicsEvidence],
        createdAt: Date(timeIntervalSince1970: 200)
    )
    let candidate = projectEvidencePack(
        projectID: "candidate",
        physicsCorpora: [candidatePhysicsEvidence],
        createdAt: Date(timeIntervalSince1970: 100)
    )

    let comparison = try TrainingProjectEvidencePackComparator().compare(
        incumbent: incumbent,
        candidate: candidate
    )

    #expect(comparison.decision == .preferCandidate)
    #expect(comparison.dominantFactor == .physicsCorpusSensorCoverage)
    #expect(comparison.incumbentScore.physicsCorpusHardwareSensorCalibrationRecordCount == 0)
    #expect(comparison.candidateScore.physicsCorpusHardwareSensorCalibrationRecordCount == 1)
    #expect(comparison.candidateScore.physicsCorpusObservedHardwareSensorSampleCount == 3)
}

@Test func trainingProjectEvidencePackComparatorPrefersContactTrainingPhysicsCorpusEvidence() throws {
    let incumbentPhysicsEvidence = TrainingProjectEvidencePack.PhysicsCorpusEvidence(
        summary: projectEvidenceDescriptorCorpusSummary(),
        path: "physics/incumbent-descriptor-corpus-acceptance.json"
    )
    let candidatePhysicsEvidence = TrainingProjectEvidencePack.PhysicsCorpusEvidence(
        summary: projectEvidenceDescriptorCorpusSummary(
            requiredReadiness: .contactTraining,
            contactReplay: projectEvidenceContactReplayEvidence()
        ),
        path: "physics/candidate-descriptor-corpus-acceptance.json"
    )
    let incumbent = projectEvidencePack(
        projectID: "incumbent",
        physicsCorpora: [incumbentPhysicsEvidence],
        createdAt: Date(timeIntervalSince1970: 200)
    )
    let candidate = projectEvidencePack(
        projectID: "candidate",
        physicsCorpora: [candidatePhysicsEvidence],
        createdAt: Date(timeIntervalSince1970: 100)
    )

    let comparison = try TrainingProjectEvidencePackComparator().compare(
        incumbent: incumbent,
        candidate: candidate
    )

    #expect(comparison.decision == .preferCandidate)
    #expect(comparison.dominantFactor == .physicsCorpusContactReplay)
    #expect(comparison.incumbentScore.physicsCorpusAcceptedRecordCount == 1)
    #expect(comparison.candidateScore.physicsCorpusAcceptedRecordCount == 1)
    #expect(comparison.incumbentScore.physicsCorpusContactReplayRecordCount == 0)
    #expect(comparison.candidateScore.physicsCorpusContactReplayRecordCount == 1)
}

@Test func trainingProjectEvidencePackComparatorKeepsHardwareParityOverContactTrainingCorpusEvidence() throws {
    let incumbentPhysicsEvidence = TrainingProjectEvidencePack.PhysicsCorpusEvidence(
        summary: projectEvidenceDescriptorCorpusSummary(
            requiredReadiness: .hardwareParity,
            hardwareParity: .accepted,
            hardwareEvidence: projectEvidenceHardwareEvidence(reportHash: "hardware-report-hash-a")
        ),
        path: "physics/incumbent-descriptor-corpus-acceptance.json"
    )
    let candidatePhysicsEvidence = TrainingProjectEvidencePack.PhysicsCorpusEvidence(
        summary: projectEvidenceDescriptorCorpusSummary(
            requiredReadiness: .contactTraining,
            contactReplay: projectEvidenceContactReplayEvidence()
        ),
        path: "physics/candidate-descriptor-corpus-acceptance.json"
    )
    let incumbent = projectEvidencePack(
        projectID: "incumbent",
        physicsCorpora: [incumbentPhysicsEvidence],
        createdAt: Date(timeIntervalSince1970: 100)
    )
    let candidate = projectEvidencePack(
        projectID: "candidate",
        physicsCorpora: [candidatePhysicsEvidence],
        createdAt: Date(timeIntervalSince1970: 200)
    )

    let comparison = try TrainingProjectEvidencePackComparator().compare(
        incumbent: incumbent,
        candidate: candidate
    )

    #expect(comparison.decision == .keepIncumbent)
    #expect(comparison.dominantFactor == .physicsCorpusAcceptedHardwareParity)
    #expect(comparison.incumbentScore.physicsCorpusAcceptedHardwareParityRecordCount == 1)
    #expect(comparison.candidateScore.physicsCorpusAcceptedHardwareParityRecordCount == 0)
    #expect(comparison.candidateScore.physicsCorpusContactReplayRecordCount == 1)
}

@Test func trainingProjectEvidencePackComparatorPrefersCandidateWithObservabilityEvidence() throws {
    let artifact = projectEvidenceObservabilityArtifact()
    let incumbent = projectEvidencePack(projectID: "incumbent")
    let candidate = projectEvidencePack(
        projectID: "candidate",
        observabilityArtifacts: [
            TrainingProjectEvidencePack.ObservabilityArtifactEvidence(
                artifact: artifact,
                path: "observability/conscious-unconscious-observability.json"
            ),
        ]
    )

    let comparison = try TrainingProjectEvidencePackComparator().compare(
        incumbent: incumbent,
        candidate: candidate
    )

    #expect(comparison.decision == .preferCandidate)
    #expect(comparison.dominantFactor == .observabilityArtifacts)
    #expect(comparison.candidateScore.observabilityArtifactCount == 1)
}

@Test func trainingProjectEvidencePackComparatorPrefersReferenceM2StressCoverage() throws {
    let genericStressEvidence = TrainingProjectEvidencePack.StressSuiteEvidence(
        suiteID: "reference-generic-stress",
        profile: .referenceQuadrotor,
        recordCount: 3,
        coverageTargets: [
            TrainingProjectEvidencePack.StressCoverageTargetEvidence(
                dimension: .longHorizon,
                minimumCount: 1,
                actualCount: 3
            ),
        ],
        replayStatus: .performed,
        replayCheckCount: 3,
        path: "stress/reference-generic-stress.json"
    )
    let m2StressEvidence = TrainingProjectEvidencePack.StressSuiteEvidence(
        manifest: try projectEvidenceM2StressManifest(),
        path: "stress/reference-m2-stress.json"
    )
    let incumbent = projectEvidencePack(
        projectID: "incumbent",
        stressSuites: [genericStressEvidence],
        createdAt: Date(timeIntervalSince1970: 200)
    )
    let candidate = projectEvidencePack(
        projectID: "candidate",
        stressSuites: [m2StressEvidence],
        createdAt: Date(timeIntervalSince1970: 100)
    )

    let comparison = try TrainingProjectEvidencePackComparator().compare(
        incumbent: incumbent,
        candidate: candidate
    )

    #expect(comparison.decision == .preferCandidate)
    #expect(comparison.dominantFactor == .referenceM2StressCoverage)
    #expect(!comparison.incumbentScore.referenceM2StressCoverageComplete)
    #expect(comparison.candidateScore.referenceM2StressCoverageComplete)
}

@Test func trainingProjectEvidencePackComparatorReportsEquivalentEvidence() throws {
    let pack = projectEvidencePack(projectID: "reference-foundation")

    let comparison = try TrainingProjectEvidencePackComparator().compare(
        incumbent: pack,
        candidate: pack
    )

    #expect(comparison.decision == .equivalent)
    #expect(comparison.dominantFactor == .equivalent)
}

@Test func trainingProjectEvidencePackComparatorRejectsInvalidCandidateBeforeScoring() throws {
    let incumbent = projectEvidencePack(projectID: "incumbent")
    let candidate = projectEvidencePack(projectID: " ")

    #expect(throws: TrainingProjectEvidencePackValidator.ValidationError.emptyProjectID) {
        _ = try TrainingProjectEvidencePackComparator().compare(
            incumbent: incumbent,
            candidate: candidate
        )
    }
}

@Test func trainingDatasetCurationPolicyValidatorAcceptsRawMetadataCoverage() throws {
    let policy = TrainingDatasetCurationPolicy(
        policyID: "reference-attitude-curation",
        minimumDatasetCount: 2,
        minimumTotalRecordCount: 32,
        minimumRecordCountPerDataset: 16,
        requiredScenarioIDs: ["scenario-1", "scenario-2"],
        allowedDeterminismTiers: ["tier1"],
        expectedChannelCount: 4,
        expectedDriveCount: 4,
        requiresRewardDescriptor: true,
        requiresProvenance: true
    )

    let report = try TrainingDatasetCurationPolicyValidator().validate(
        metadata: [
            projectEvidenceMetadata(id: "episode-a", seed: 1, recordCount: 16),
            projectEvidenceMetadata(id: "episode-b", seed: 2, recordCount: 32),
        ],
        policy: policy
    )

    #expect(report.accepted)
    #expect(report.datasetCount == 2)
    #expect(report.totalRecordCount == 48)
    #expect(report.scenarioIDs == ["scenario-1", "scenario-2"])
}

@Test func trainingDatasetCurationPolicyValidatorRejectsMissingScenarioCoverage() throws {
    let policy = TrainingDatasetCurationPolicy(
        policyID: "reference-attitude-curation",
        requiredScenarioIDs: ["scenario-1", "scenario-2"]
    )

    #expect(throws: TrainingDatasetCurationPolicyValidator.ValidationError
        .missingRequiredScenarioID("scenario-2")) {
        _ = try TrainingDatasetCurationPolicyValidator().validate(
            metadata: [projectEvidenceMetadata(id: "episode-a", seed: 1)],
            policy: policy
        )
    }
}

@Test func trainingDatasetCurationPolicyValidatorRejectsRawMetadataRequirementForProjectEvidencePack() throws {
    let policy = TrainingDatasetCurationPolicy(
        policyID: "reference-attitude-curation",
        allowedDeterminismTiers: ["tier1"]
    )

    #expect(throws: TrainingDatasetCurationPolicyValidator.ValidationError
        .projectEvidenceCannotValidateRawMetadataRequirement("allowedDeterminismTiers")) {
        _ = try TrainingDatasetCurationPolicyValidator().validate(
            projectEvidencePack: projectEvidencePack(projectID: "reference-foundation"),
            policy: policy
        )
    }
}

@Test func trainingDatasetCurationPolicyValidatorAcceptsProjectEvidencePackCoverage() throws {
    let policy = TrainingDatasetCurationPolicy(
        policyID: "reference-attitude-pack-curation",
        minimumDatasetCount: 1,
        minimumTotalRecordCount: 16,
        minimumRecordCountPerDataset: 16,
        requiredScenarioIDs: ["scenario-1"],
        requiresRewardDescriptor: true,
        requiresProvenance: true
    )

    let report = try TrainingDatasetCurationPolicyValidator().validate(
        projectEvidencePack: projectEvidencePack(projectID: "reference-foundation"),
        policy: policy
    )

    #expect(report.accepted)
    #expect(report.datasetIDs == ["episode-a"])
    #expect(report.scenarioIDs == ["scenario-1"])
}

private func projectEvidencePack(
    projectID: String,
    datasets: [TrainingDatasetMetadata] = [projectEvidenceMetadata(id: "episode-a")],
    checkpoint: CheckpointDecision = projectEvidenceAcceptedCheckpointDecision(),
    regressionArtifacts: [TrainingProjectEvidencePack.RegressionArtifactReference] = [
        projectEvidenceRegressionArtifact(),
    ],
    stressSuites: [TrainingProjectEvidencePack.StressSuiteEvidence] = [],
    physicsCorpora: [TrainingProjectEvidencePack.PhysicsCorpusEvidence] = [],
    observabilityArtifacts: [TrainingProjectEvidencePack.ObservabilityArtifactEvidence] = [],
    createdAt: Date = Date(timeIntervalSince1970: 100)
) -> TrainingProjectEvidencePack {
    TrainingProjectEvidencePack(
        projectID: projectID,
        createdAt: createdAt,
        datasets: datasets.map(TrainingProjectEvidencePack.DatasetLineageRecord.init),
        curriculumStages: projectEvidenceCurriculum().trainingStages.map(
            TrainingProjectEvidencePack.CurriculumStageEvidence.init
        ),
        checkpoint: TrainingProjectEvidencePack.CheckpointEvidence(decision: checkpoint),
        regressionArtifacts: regressionArtifacts,
        stressSuites: stressSuites,
        physicsCorpora: physicsCorpora,
        observabilityArtifacts: observabilityArtifacts
    )
}

private func projectEvidenceMetadata(
    id: String,
    seed: UInt64 = 1,
    recordCount: Int = 16
) -> TrainingDatasetMetadata {
    TrainingDatasetMetadata(
        scenarioId: "scenario-\(seed)",
        seed: seed,
        timeStep: 0.001,
        determinismTier: "tier1",
        configHash: "config-\(seed)",
        channelCount: 4,
        driveCount: 4,
        recordCount: recordCount,
        episodeId: id,
        rewardDescriptor: RewardDescriptor(id: "reward", version: "1", configHash: "reward-config"),
        provenance: TrainingProvenanceManifest(
            codeHash: "code",
            configHash: "config-\(seed)",
            robotManifestHash: "robot",
            suiteVersion: "suite-v1"
        )
    )
}

private func projectEvidenceCurriculum() -> LearningProjectCurriculum {
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

private func projectEvidenceAcceptedCheckpointDecision() -> CheckpointDecision {
    CheckpointDecision(
        runID: "run-a",
        state: .accepted,
        reason: "accepted",
        candidateCheckpointID: "candidate-a",
        candidateCheckpointURL: URL(fileURLWithPath: "/tmp/candidate-a"),
        publishedCheckpointURL: URL(fileURLWithPath: "/tmp/published-a"),
        decidedAt: Date(timeIntervalSince1970: 10)
    )
}

private func projectEvidenceStagedCheckpointDecision() -> CheckpointDecision {
    CheckpointDecision(
        runID: "run-b",
        state: .staged,
        reason: "staged",
        candidateCheckpointID: "candidate-b",
        candidateCheckpointURL: URL(fileURLWithPath: "/tmp/candidate-b"),
        publishedCheckpointURL: nil,
        decidedAt: Date(timeIntervalSince1970: 11)
    )
}

private func projectEvidenceRegressionArtifact(
    path: String = "evaluations/final/checkpoint-evaluation.json",
    accepted: Bool = true
) -> TrainingProjectEvidencePack.RegressionArtifactReference {
    TrainingProjectEvidencePack.RegressionArtifactReference(
        kind: "checkpoint-evaluation",
        path: path,
        accepted: accepted
    )
}

private func projectEvidenceStressManifest(
    suiteID: String = "reference-attitude-stress",
    scenarioID: String = "reference-attitude-stress-scenario",
    seed: UInt64 = 7
) throws -> StressSuiteManifest {
    let record = try StressSuiteManifest.ScenarioRecord(
        scenarioID: scenarioID,
        seed: seed,
        duration: 20,
        timeStep: TimeStep(delta: 0.001),
        configHash: "stress-config",
        dimensions: [.hfLatencySpike, .longHorizon]
    )
    return try StressSuiteManifest(
        suiteID: suiteID,
        profile: .referenceQuadrotor,
        records: [record],
        coverageTargets: [
            StressSuiteManifest.CoverageTarget(dimension: .hfLatencySpike, minimumCount: 1),
            StressSuiteManifest.CoverageTarget(dimension: .longHorizon, minimumCount: 1),
        ],
        replayRequirement: .performedRequired,
        replay: .performed([
            ReplayCheckResult(
                scenarioId: ScenarioID(scenarioID),
                seed: ScenarioSeed(seed),
                tier: .tier1,
                passed: true,
                issues: [],
                residuals: .zero
            ),
        ])
    )
}

private func projectEvidenceM2StressManifest() throws -> StressSuiteManifest {
    let benchmark = try LongHorizonBenchmarkSuite.makeDefault(
        scenariosPerTrack: 1,
        baseSeed: 60_000
    )
    let definitions = benchmark.cases.map(\.definition)
    return try StressSuiteManifest.referenceQuadrotorM2Benchmark(
        suiteID: "reference-m2-stress",
        benchmark: benchmark,
        replay: .performed(
            definitions.map { definition in
                ReplayCheckResult(
                    scenarioId: definition.config.id,
                    seed: definition.config.seed,
                    tier: .tier1,
                    passed: true,
                    issues: [],
                    residuals: .zero
                )
            }
        )
    )
}

private func projectEvidenceDescriptorCorpusSummary(
    corpusID: String = "reference-physics-corpus",
    entryID: String = "reference-physics-entry",
    requiredReadiness: ReadinessLevel = .dynamicSimulation,
    hardwareParity: DescriptorCorpusHardwareParityStatus = .notRequested,
    hardwareEvidence: DescriptorCorpusHardwareEvidence? = nil,
    contactReplay: DescriptorCorpusContactReplayEvidence? = nil,
    readinessGaps: [DescriptorCorpusReadinessGap] = []
) -> DescriptorCorpusAcceptanceSummary {
    DescriptorCorpusAcceptanceSummary(
        corpusID: corpusID,
        generatedAt: "1970-01-01T00:00:00Z",
        records: [
            DescriptorCorpusAcceptanceRecord(
                entryID: entryID,
                robotID: "reference-robot",
                label: "Reference Robot",
                bodyID: "reference-body",
                worldID: "reference-world",
                embodimentContractID: "reference-embodiment",
                requiredReadiness: requiredReadiness,
                achievedReadiness: requiredReadiness,
                hardwareParity: hardwareParity,
                hardwareEvidence: hardwareEvidence,
                readinessGaps: readinessGaps,
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

private func projectEvidenceContactReplayEvidence() -> DescriptorCorpusContactReplayEvidence {
    DescriptorCorpusContactReplayEvidence(
        maxActiveContactCount: 2,
        maxPenetration: 0.001,
        maxNormalImpulse: 0.02,
        maxNormalForce: 0.3,
        maxSolverIterations: 4
    )
}

private func projectEvidenceHardwareEvidence(
    reportHash: String,
    measurementSystem: String = "bench-measurement",
    deviceID: String? = "measurement-device-a",
    jointCalibrationCount: Int = 1,
    jointSampleCount: Int = 3,
    measuredJointSampleCount: Int = 3,
    observedJointSampleCount: Int = 3,
    sensorCalibrationCount: Int = 0,
    sensorSampleCount: Int = 0,
    observedSensorSampleCount: Int = 0
) -> DescriptorCorpusHardwareEvidence {
    DescriptorCorpusHardwareEvidence(
        reportID: "hardware-report-a",
        robotID: "reference-robot",
        bodyID: "reference-body",
        embodimentContractID: "reference-embodiment",
        reportHash: reportHash,
        readinessLevel: .hardwareParity,
        measurementSystem: measurementSystem,
        deviceID: deviceID,
        jointCalibrationCount: jointCalibrationCount,
        jointSampleCount: jointSampleCount,
        measuredJointSampleCount: measuredJointSampleCount,
        observedJointSampleCount: observedJointSampleCount,
        sensorCalibrationCount: sensorCalibrationCount,
        sensorSampleCount: sensorSampleCount,
        observedSensorSampleCount: observedSensorSampleCount,
        contactCalibrationCount: 0,
        contactSampleCount: 0
    )
}

private func projectEvidenceObservabilityArtifact(
    runID: String = "run-a",
    scenarioID: String = "scenario-1",
    seed: UInt64? = 1
) -> ConsciousUnconsciousObservabilityArtifact {
    ConsciousUnconsciousObservabilityArtifact(
        runID: runID,
        scenarioID: scenarioID,
        seed: seed,
        timeStep: 0.001,
        descendingSnapshots: [
            projectEvidenceDescendingSnapshot(),
        ],
        upwardSummaries: [
            projectEvidenceUpwardSummary(),
        ],
        arbitrationDecisions: [
            projectEvidenceArbitrationDecision(),
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

private func projectEvidenceDescendingSnapshot() -> ConsciousUnconsciousObservabilityArtifact.DescendingSnapshot {
    ConsciousUnconsciousObservabilityArtifact.DescendingSnapshot(
        stepIndex: 0,
        timestamp: 0,
        source: "planner",
        goalID: "hold-attitude",
        priority: 0.7,
        inhibition: 0.1,
        contextHash: "context-hash"
    )
}

private func projectEvidenceUpwardSummary() -> ConsciousUnconsciousObservabilityArtifact.UpwardSummary {
    ConsciousUnconsciousObservabilityArtifact.UpwardSummary(
        stepIndex: 0,
        timestamp: 0,
        channels: projectEvidenceSummaryChannels()
    )
}

private func projectEvidenceSummaryChannels() -> [ConsciousUnconsciousObservabilityArtifact.ScalarChannel] {
    [
        ConsciousUnconsciousObservabilityArtifact.ScalarChannel(name: "salience", stableIndex: 0, value: 0.4),
        ConsciousUnconsciousObservabilityArtifact.ScalarChannel(name: "risk", stableIndex: 1, value: 0.2),
        ConsciousUnconsciousObservabilityArtifact.ScalarChannel(name: "uncertainty", stableIndex: 2, value: 0.3),
        ConsciousUnconsciousObservabilityArtifact.ScalarChannel(
            name: "constraintPressure",
            stableIndex: 3,
            value: 0.5
        ),
        ConsciousUnconsciousObservabilityArtifact.ScalarChannel(name: "recoveryState", stableIndex: 4, value: 0.8),
    ]
}

private func projectEvidenceArbitrationDecision() -> ConsciousUnconsciousObservabilityArtifact.ArbitrationDecision {
    ConsciousUnconsciousObservabilityArtifact.ArbitrationDecision(
        stepIndex: 0,
        timestamp: 0,
        coreDriveMagnitude: 0.7,
        reflexCorrectionMagnitude: 0.3,
        finalDriveMagnitude: 0.5,
        reflexPreemptedDescendingBias: true,
        reason: "reflex reduced conflicting descending priority"
    )
}

private func projectEvidenceTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-training-project-evidence-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func projectEvidenceCreateFile(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{}".write(to: url, atomically: true, encoding: .utf8)
}

private func projectEvidenceWriteJSON<T: Encodable>(_ value: T, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: url, options: [.atomic])
}

private func projectEvidenceCleanup(_ directory: URL) {
    do {
        try FileManager.default.removeItem(at: directory)
    } catch {
        Issue.record("Failed to remove temporary directory: \(error)")
    }
}
