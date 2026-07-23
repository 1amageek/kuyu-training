import Foundation

public struct TrainingProjectEvidencePackComparator: Sendable {
    private let validator: TrainingProjectEvidencePackValidator

    public init(
        validator: TrainingProjectEvidencePackValidator = TrainingProjectEvidencePackValidator()
    ) {
        self.validator = validator
    }

    public func compare(
        incumbent: TrainingProjectEvidencePack,
        candidate: TrainingProjectEvidencePack
    ) throws -> TrainingProjectEvidencePackComparison {
        try validator.validate(incumbent)
        try validator.validate(candidate)

        let incumbentScore = score(incumbent)
        let candidateScore = score(candidate)
        let decision: TrainingProjectEvidencePackComparison.Decision
        if candidateScore > incumbentScore {
            decision = .preferCandidate
        } else if candidateScore < incumbentScore {
            decision = .keepIncumbent
        } else {
            decision = .equivalent
        }

        return TrainingProjectEvidencePackComparison(
            incumbentProjectID: incumbent.projectID,
            candidateProjectID: candidate.projectID,
            decision: decision,
            dominantFactor: dominantFactor(incumbentScore: incumbentScore, candidateScore: candidateScore),
            incumbentScore: incumbentScore,
            candidateScore: candidateScore
        )
    }

    public func score(
        _ pack: TrainingProjectEvidencePack
    ) -> TrainingProjectEvidencePackComparison.Score {
        let hardwareMeasurementSystems = Set(pack.physicsCorpora.flatMap(\.hardwareEvidenceMeasurementSystems))
        let hardwareMeasurementDeviceIDs = Set(pack.physicsCorpora.flatMap(\.hardwareEvidenceDeviceIDs))
        let hardwareReportHashes = Set(pack.physicsCorpora.flatMap(\.hardwareEvidenceReportHashes))
        return TrainingProjectEvidencePackComparison.Score(
            checkpointState: pack.checkpoint.state,
            checkpointRank: checkpointRank(pack.checkpoint.state),
            acceptedRegressionArtifactCount: pack.regressionArtifacts.filter(\.accepted).count,
            totalRegressionArtifactCount: pack.regressionArtifacts.count,
            physicsCorpusCount: pack.physicsCorpora.count,
            physicsCorpusAcceptedRecordCount: pack.physicsCorpora.reduce(0) { $0 + $1.acceptedRecordCount },
            physicsCorpusAcceptedHardwareParityRecordCount: pack.physicsCorpora.reduce(0) {
                $0 + $1.acceptedHardwareParityRecordCount
            },
            physicsCorpusHardwareEvidenceRecordCount: pack.physicsCorpora.reduce(0) {
                $0 + $1.hardwareEvidenceRecordCount
            },
            physicsCorpusHardwareMeasurementSystemCount: hardwareMeasurementSystems.count,
            physicsCorpusHardwareMeasurementDeviceIDCount: hardwareMeasurementDeviceIDs.count,
            physicsCorpusHardwareReportHashCount: hardwareReportHashes.count,
            physicsCorpusHardwareJointCalibrationRecordCount: pack.physicsCorpora.reduce(0) {
                $0 + $1.hardwareJointCalibrationRecordCount
            },
            physicsCorpusMeasuredHardwareJointSampleCount: pack.physicsCorpora.reduce(0) {
                $0 + $1.measuredHardwareJointSampleCount
            },
            physicsCorpusObservedHardwareJointSampleCount: pack.physicsCorpora.reduce(0) {
                $0 + $1.observedHardwareJointSampleCount
            },
            physicsCorpusHardwareSensorCalibrationRecordCount: pack.physicsCorpora.reduce(0) {
                $0 + $1.hardwareSensorCalibrationRecordCount
            },
            physicsCorpusObservedHardwareSensorSampleCount: pack.physicsCorpora.reduce(0) {
                $0 + $1.observedHardwareSensorSampleCount
            },
            physicsCorpusContactReplayRecordCount: pack.physicsCorpora.reduce(0) {
                $0 + $1.contactReplayRecordCount
            },
            referenceM2StressCoverageComplete: validator.referenceM2StressCoverageComplete(in: pack),
            observabilityArtifactCount: pack.observabilityArtifacts.count,
            observabilitySampleCount: pack.observabilityArtifacts.reduce(0) {
                $0 + $1.descendingSnapshotCount + $1.upwardSummaryCount + $1.arbitrationDecisionCount
            },
            stressSuiteCount: pack.stressSuites.count,
            stressScenarioRecordCount: pack.stressSuites.reduce(0) { $0 + $1.recordCount },
            datasetRecordCount: pack.datasets.reduce(0) { $0 + $1.recordCount },
            datasetCount: pack.datasets.count,
            curriculumStageCount: pack.curriculumStages.count,
            createdAt: pack.createdAt
        )
    }

    private func dominantFactor(
        incumbentScore: TrainingProjectEvidencePackComparison.Score,
        candidateScore: TrainingProjectEvidencePackComparison.Score
    ) -> TrainingProjectEvidencePackComparison.DominantFactor {
        if incumbentScore.checkpointRank != candidateScore.checkpointRank {
            return .checkpointState
        }
        if incumbentScore.acceptedRegressionArtifactCount != candidateScore.acceptedRegressionArtifactCount {
            return .acceptedRegressionArtifacts
        }
        if incumbentScore.totalRegressionArtifactCount != candidateScore.totalRegressionArtifactCount {
            return .totalRegressionArtifacts
        }
        if incumbentScore.physicsCorpusCount != candidateScore.physicsCorpusCount {
            return .physicsCorpora
        }
        if incumbentScore.physicsCorpusAcceptedRecordCount != candidateScore.physicsCorpusAcceptedRecordCount {
            return .physicsCorpusRecords
        }
        if incumbentScore.physicsCorpusAcceptedHardwareParityRecordCount
            != candidateScore.physicsCorpusAcceptedHardwareParityRecordCount {
            return .physicsCorpusAcceptedHardwareParity
        }
        if incumbentScore.physicsCorpusHardwareEvidenceRecordCount
            != candidateScore.physicsCorpusHardwareEvidenceRecordCount {
            return .physicsCorpusHardwareEvidence
        }
        if incumbentScore.physicsCorpusHardwareMeasurementSystemCount
            != candidateScore.physicsCorpusHardwareMeasurementSystemCount {
            return .physicsCorpusMeasurementSystems
        }
        if incumbentScore.physicsCorpusHardwareMeasurementDeviceIDCount
            != candidateScore.physicsCorpusHardwareMeasurementDeviceIDCount {
            return .physicsCorpusMeasurementDevices
        }
        if incumbentScore.physicsCorpusHardwareReportHashCount != candidateScore.physicsCorpusHardwareReportHashCount {
            return .physicsCorpusHardwareReports
        }
        if incumbentScore.physicsCorpusHardwareJointCalibrationRecordCount
            != candidateScore.physicsCorpusHardwareJointCalibrationRecordCount {
            return .physicsCorpusJointCoverage
        }
        if incumbentScore.physicsCorpusMeasuredHardwareJointSampleCount
            != candidateScore.physicsCorpusMeasuredHardwareJointSampleCount {
            return .physicsCorpusJointCoverage
        }
        if incumbentScore.physicsCorpusObservedHardwareJointSampleCount
            != candidateScore.physicsCorpusObservedHardwareJointSampleCount {
            return .physicsCorpusJointCoverage
        }
        if incumbentScore.physicsCorpusHardwareSensorCalibrationRecordCount
            != candidateScore.physicsCorpusHardwareSensorCalibrationRecordCount {
            return .physicsCorpusSensorCoverage
        }
        if incumbentScore.physicsCorpusObservedHardwareSensorSampleCount
            != candidateScore.physicsCorpusObservedHardwareSensorSampleCount {
            return .physicsCorpusSensorCoverage
        }
        if incumbentScore.physicsCorpusContactReplayRecordCount
            != candidateScore.physicsCorpusContactReplayRecordCount {
            return .physicsCorpusContactReplay
        }
        if incumbentScore.referenceM2StressCoverageComplete != candidateScore.referenceM2StressCoverageComplete {
            return .referenceM2StressCoverage
        }
        if incumbentScore.observabilityArtifactCount != candidateScore.observabilityArtifactCount {
            return .observabilityArtifacts
        }
        if incumbentScore.observabilitySampleCount != candidateScore.observabilitySampleCount {
            return .observabilitySamples
        }
        if incumbentScore.stressSuiteCount != candidateScore.stressSuiteCount {
            return .stressSuites
        }
        if incumbentScore.stressScenarioRecordCount != candidateScore.stressScenarioRecordCount {
            return .stressScenarioRecords
        }
        if incumbentScore.datasetRecordCount != candidateScore.datasetRecordCount {
            return .datasetRecords
        }
        if incumbentScore.datasetCount != candidateScore.datasetCount {
            return .datasetCount
        }
        if incumbentScore.curriculumStageCount != candidateScore.curriculumStageCount {
            return .curriculumStages
        }
        if incumbentScore.createdAt != candidateScore.createdAt {
            return .createdAt
        }
        return .equivalent
    }

    private func checkpointRank(_ state: CheckpointDecisionState) -> Int {
        switch state {
        case .accepted:
            return 50
        case .staged:
            return 40
        case .rejected:
            return 20
        case .skipped:
            return 10
        case .failed:
            return 0
        }
    }
}
