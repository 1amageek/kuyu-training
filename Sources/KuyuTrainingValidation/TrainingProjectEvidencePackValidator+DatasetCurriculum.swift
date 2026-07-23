import Foundation

extension TrainingProjectEvidencePackValidator {
    func validateDatasets(
        _ datasets: [TrainingProjectEvidencePack.DatasetLineageRecord]
    ) throws {
        guard !datasets.isEmpty else { throw ValidationError.emptyDatasetLineage }
        var datasetIDs: Set<String> = []
        for dataset in datasets {
            let datasetID = dataset.datasetID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !datasetID.isEmpty else { throw ValidationError.emptyDatasetID }
            guard datasetIDs.insert(datasetID).inserted else {
                throw ValidationError.duplicateDatasetID(datasetID)
            }
            guard !dataset.scenarioID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.emptyScenarioID(datasetID)
            }
            guard dataset.recordCount > 0 else {
                throw ValidationError.invalidDatasetRecordCount(
                    datasetID: datasetID,
                    recordCount: dataset.recordCount
                )
            }
            guard !dataset.configHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.emptyDatasetConfigHash(datasetID)
            }
            try validateRewardDescriptorFields(dataset)
        }
    }

    func validateRewardDescriptorFields(
        _ dataset: TrainingProjectEvidencePack.DatasetLineageRecord
    ) throws {
        let fields = [
            ("rewardDescriptorID", dataset.rewardDescriptorID),
            ("rewardDescriptorVersion", dataset.rewardDescriptorVersion),
            ("rewardDescriptorConfigHash", dataset.rewardDescriptorConfigHash),
        ]
        let hasAnyField = fields.contains { _, value in
            value != nil
        }
        guard hasAnyField else { return }
        for (field, value) in fields {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else {
                throw ValidationError.emptyRewardDescriptorField(datasetID: dataset.datasetID, field: field)
            }
        }
    }

    func validateCurriculumStages(
        _ stages: [TrainingProjectEvidencePack.CurriculumStageEvidence]
    ) throws {
        guard !stages.isEmpty else { throw ValidationError.emptyCurriculumStages }
        var stageIDs: Set<String> = []
        for stage in stages {
            let stageID = stage.stageID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stageID.isEmpty else { throw ValidationError.emptyStageID }
            guard stageIDs.insert(stageID).inserted else {
                throw ValidationError.duplicateStageID(stageID)
            }
            if let producedArtifactID = stage.producedArtifactID {
                guard !producedArtifactID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ValidationError.emptyProducedArtifactID(stageID: stageID)
                }
            }
            guard stage.seedCount > 0,
                  stage.episodesPerSuite > 0,
                  stage.generationLimit > 0,
                  !stage.suiteIDs.isEmpty else {
                throw ValidationError.invalidStageBudget(stageID: stageID)
            }
        }
        for stage in stages {
            for dependencyID in stage.dependsOnStageIDs {
                guard stageIDs.contains(dependencyID) else {
                    throw ValidationError.missingStageDependency(
                        stageID: stage.stageID,
                        dependencyID: dependencyID
                    )
                }
            }
        }
    }
}
