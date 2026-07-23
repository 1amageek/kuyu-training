import Foundation
import KuyuScenarios
import KuyuTrainingContracts

public struct TrainingProjectEvidencePackValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable {
        case unsupportedSchemaVersion(Int)
        case emptyProjectID
        case emptyDatasetLineage
        case emptyDatasetID
        case duplicateDatasetID(String)
        case emptyScenarioID(String)
        case invalidDatasetRecordCount(datasetID: String, recordCount: Int)
        case emptyDatasetConfigHash(String)
        case emptyRewardDescriptorField(datasetID: String, field: String)
        case emptyCurriculumStages
        case emptyStageID
        case duplicateStageID(String)
        case emptyProducedArtifactID(stageID: String)
        case missingStageDependency(stageID: String, dependencyID: String)
        case invalidStageBudget(stageID: String)
        case emptyCheckpointRunID
        case emptyCheckpointReason
        case acceptedCheckpointMissingCandidateID
        case acceptedCheckpointMissingCandidateURL
        case acceptedCheckpointMissingPublishedURL
        case stagedCheckpointMissingCandidateID
        case stagedCheckpointMissingCandidateURL
        case nonAcceptedCheckpointHasPublishedURL(CheckpointDecisionState)
        case emptyRegressionArtifacts
        case emptyRegressionArtifactKind
        case emptyRegressionArtifactPath
        case absoluteRegressionArtifactPath(String)
        case escapingRegressionArtifactPath(String)
        case duplicateRegressionArtifactPath(String)
        case emptyStressSuiteID
        case duplicateStressSuiteID(String)
        case invalidStressSuiteRecordCount(suiteID: String, recordCount: Int)
        case emptyStressCoverageTargets(String)
        case stressCoverageTargetNotMet(
            suiteID: String,
            dimension: StressSuiteManifest.StressDimension,
            minimumCount: Int,
            actualCount: Int
        )
        case invalidStressReplayEvidence(String)
        case emptyStressSuitePath
        case absoluteStressSuitePath(String)
        case escapingStressSuitePath(String)
        case duplicateStressSuitePath(String)
        case missingReferenceM2StressCoverage([StressSuiteManifest.StressDimension])
        case missingReferenceM2SemanticEvidence([String])
        case emptyPhysicsCorpusID
        case duplicatePhysicsCorpusID(String)
        case invalidPhysicsCorpusAcceptedRecordCount(corpusID: String, acceptedRecordCount: Int)
        case invalidPhysicsCorpusHardwareParityGapCount(corpusID: String, hardwareParityGapCount: Int)
        case invalidPhysicsCorpusHardwareEvidenceRecordCount(corpusID: String, hardwareEvidenceRecordCount: Int)
        case invalidPhysicsCorpusAcceptedHardwareParityRecordCount(
            corpusID: String,
            acceptedHardwareParityRecordCount: Int
        )
        case invalidPhysicsCorpusHardwareJointCalibrationRecordCount(
            corpusID: String,
            hardwareJointCalibrationRecordCount: Int
        )
        case invalidPhysicsCorpusHardwareJointSampleCount(corpusID: String, hardwareJointSampleCount: Int)
        case invalidPhysicsCorpusMeasuredHardwareJointSampleCount(
            corpusID: String,
            measuredHardwareJointSampleCount: Int
        )
        case invalidPhysicsCorpusObservedHardwareJointSampleCount(
            corpusID: String,
            observedHardwareJointSampleCount: Int
        )
        case invalidPhysicsCorpusHardwareSensorCalibrationRecordCount(
            corpusID: String,
            hardwareSensorCalibrationRecordCount: Int
        )
        case invalidPhysicsCorpusHardwareSensorSampleCount(corpusID: String, hardwareSensorSampleCount: Int)
        case invalidPhysicsCorpusObservedHardwareSensorSampleCount(
            corpusID: String,
            observedHardwareSensorSampleCount: Int
        )
        case missingPhysicsCorpusHardwareParityEvidence(String)
        case invalidPhysicsCorpusContactReplayRecordCount(corpusID: String, contactReplayRecordCount: Int)
        case missingPhysicsCorpusContactReplayEvidence(String)
        case emptyPhysicsCorpusHardwareEvidenceReportHash(String)
        case duplicatePhysicsCorpusHardwareEvidenceReportHash(corpusID: String, reportHash: String)
        case emptyPhysicsCorpusHardwareEvidenceMeasurementSystem(String)
        case duplicatePhysicsCorpusHardwareEvidenceMeasurementSystem(corpusID: String, measurementSystem: String)
        case emptyPhysicsCorpusHardwareEvidenceDeviceID(String)
        case duplicatePhysicsCorpusHardwareEvidenceDeviceID(corpusID: String, deviceID: String)
        case emptyPhysicsCorpusReadinessLevels(String)
        case emptyPhysicsCorpusPath
        case absolutePhysicsCorpusPath(String)
        case escapingPhysicsCorpusPath(String)
        case duplicatePhysicsCorpusPath(String)
        case emptyObservabilityRunID
        case duplicateObservabilityRunID(String)
        case emptyObservabilityScenarioID(String)
        case invalidObservabilityCount(runID: String, field: String, count: Int)
        case emptyObservabilityPath
        case absoluteObservabilityPath(String)
        case escapingObservabilityPath(String)
        case duplicateObservabilityPath(String)
    }

    public init() {}

    public func makePack(
        projectID: String,
        datasetMetadata: [TrainingDatasetMetadata],
        curriculum: LearningProjectCurriculum,
        checkpointDecision: CheckpointDecision,
        regressionArtifacts: [TrainingProjectEvidencePack.RegressionArtifactReference],
        stressSuites: [TrainingProjectEvidencePack.StressSuiteEvidence] = [],
        physicsCorpora: [TrainingProjectEvidencePack.PhysicsCorpusEvidence] = [],
        observabilityArtifacts: [TrainingProjectEvidencePack.ObservabilityArtifactEvidence] = [],
        requiresReferenceM2StressCoverage: Bool = false,
        createdAt: Date = Date()
    ) throws -> TrainingProjectEvidencePack {
        _ = try LearningProjectCurriculumStageResolver().runnableStages(in: curriculum)
        let pack = TrainingProjectEvidencePack(
            projectID: projectID,
            createdAt: createdAt,
            datasets: datasetMetadata.map(TrainingProjectEvidencePack.DatasetLineageRecord.init),
            curriculumStages: curriculum.trainingStages.map(TrainingProjectEvidencePack.CurriculumStageEvidence.init),
            checkpoint: TrainingProjectEvidencePack.CheckpointEvidence(decision: checkpointDecision),
            regressionArtifacts: regressionArtifacts,
            stressSuites: stressSuites,
            physicsCorpora: physicsCorpora,
            observabilityArtifacts: observabilityArtifacts
        )
        try validate(pack)
        if requiresReferenceM2StressCoverage {
            try validateReferenceM2StressCoverage(pack)
        }
        return pack
    }

    public func validate(_ pack: TrainingProjectEvidencePack) throws {
        guard pack.schemaVersion == TrainingProjectEvidencePack.currentSchemaVersion else {
            throw ValidationError.unsupportedSchemaVersion(pack.schemaVersion)
        }
        guard !pack.projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyProjectID
        }
        try validateDatasets(pack.datasets)
        try validateCurriculumStages(pack.curriculumStages)
        try validateCheckpoint(pack.checkpoint)
        try validateRegressionArtifacts(pack.regressionArtifacts)
        try validateStressSuites(pack.stressSuites)
        try validatePhysicsCorpora(pack.physicsCorpora)
        try validateObservabilityArtifacts(pack.observabilityArtifacts)
    }

    public func validateReferenceM2StressCoverage(
        _ pack: TrainingProjectEvidencePack
    ) throws {
        try validate(pack)
        guard referenceM2StressCoverageComplete(in: pack) else {
            let missingDimensions = missingReferenceM2StressDimensions(in: pack)
            if missingDimensions.isEmpty {
                throw ValidationError.missingReferenceM2SemanticEvidence(
                    referenceQuadrotorStressSuiteIDs(in: pack)
                )
            }
            throw ValidationError.missingReferenceM2StressCoverage(missingDimensions)
        }
    }

    public func referenceM2StressCoverageComplete(
        in pack: TrainingProjectEvidencePack
    ) -> Bool {
        pack.stressSuites.contains { suite in
            suite.coversReferenceM2Benchmark
        }
    }
}
