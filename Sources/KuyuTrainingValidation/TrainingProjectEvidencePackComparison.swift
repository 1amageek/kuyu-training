import Foundation

public struct TrainingProjectEvidencePackComparison: Sendable, Codable, Equatable {
    public enum Decision: String, Sendable, Codable, Equatable {
        case preferCandidate
        case keepIncumbent
        case equivalent
    }

    public enum DominantFactor: String, Sendable, Codable, Equatable {
        case checkpointState
        case acceptedRegressionArtifacts
        case totalRegressionArtifacts
        case physicsCorpora
        case physicsCorpusRecords
        case physicsCorpusAcceptedHardwareParity
        case physicsCorpusHardwareEvidence
        case physicsCorpusMeasurementSystems
        case physicsCorpusMeasurementDevices
        case physicsCorpusHardwareReports
        case physicsCorpusJointCoverage
        case physicsCorpusSensorCoverage
        case physicsCorpusContactReplay
        case referenceM2StressCoverage
        case observabilityArtifacts
        case observabilitySamples
        case stressSuites
        case stressScenarioRecords
        case datasetRecords
        case datasetCount
        case curriculumStages
        case createdAt
        case equivalent
    }

    public struct Score: Sendable, Codable, Equatable, Comparable {
        public let checkpointState: CheckpointDecisionState
        public let checkpointRank: Int
        public let acceptedRegressionArtifactCount: Int
        public let totalRegressionArtifactCount: Int
        public let physicsCorpusCount: Int
        public let physicsCorpusAcceptedRecordCount: Int
        public let physicsCorpusAcceptedHardwareParityRecordCount: Int
        public let physicsCorpusHardwareEvidenceRecordCount: Int
        public let physicsCorpusHardwareMeasurementSystemCount: Int
        public let physicsCorpusHardwareMeasurementDeviceIDCount: Int
        public let physicsCorpusHardwareReportHashCount: Int
        public let physicsCorpusHardwareJointCalibrationRecordCount: Int
        public let physicsCorpusMeasuredHardwareJointSampleCount: Int
        public let physicsCorpusObservedHardwareJointSampleCount: Int
        public let physicsCorpusHardwareSensorCalibrationRecordCount: Int
        public let physicsCorpusObservedHardwareSensorSampleCount: Int
        public let physicsCorpusContactReplayRecordCount: Int
        public let referenceM2StressCoverageComplete: Bool
        public let observabilityArtifactCount: Int
        public let observabilitySampleCount: Int
        public let stressSuiteCount: Int
        public let stressScenarioRecordCount: Int
        public let datasetRecordCount: Int
        public let datasetCount: Int
        public let curriculumStageCount: Int
        public let createdAt: Date

        public init(
            checkpointState: CheckpointDecisionState,
            checkpointRank: Int,
            acceptedRegressionArtifactCount: Int,
            totalRegressionArtifactCount: Int,
            physicsCorpusCount: Int,
            physicsCorpusAcceptedRecordCount: Int,
            physicsCorpusAcceptedHardwareParityRecordCount: Int = 0,
            physicsCorpusHardwareEvidenceRecordCount: Int = 0,
            physicsCorpusHardwareMeasurementSystemCount: Int = 0,
            physicsCorpusHardwareMeasurementDeviceIDCount: Int = 0,
            physicsCorpusHardwareReportHashCount: Int = 0,
            physicsCorpusHardwareJointCalibrationRecordCount: Int = 0,
            physicsCorpusMeasuredHardwareJointSampleCount: Int = 0,
            physicsCorpusObservedHardwareJointSampleCount: Int = 0,
            physicsCorpusHardwareSensorCalibrationRecordCount: Int = 0,
            physicsCorpusObservedHardwareSensorSampleCount: Int = 0,
            physicsCorpusContactReplayRecordCount: Int = 0,
            referenceM2StressCoverageComplete: Bool,
            observabilityArtifactCount: Int,
            observabilitySampleCount: Int,
            stressSuiteCount: Int,
            stressScenarioRecordCount: Int,
            datasetRecordCount: Int,
            datasetCount: Int,
            curriculumStageCount: Int,
            createdAt: Date
        ) {
            self.checkpointState = checkpointState
            self.checkpointRank = checkpointRank
            self.acceptedRegressionArtifactCount = acceptedRegressionArtifactCount
            self.totalRegressionArtifactCount = totalRegressionArtifactCount
            self.physicsCorpusCount = physicsCorpusCount
            self.physicsCorpusAcceptedRecordCount = physicsCorpusAcceptedRecordCount
            self.physicsCorpusAcceptedHardwareParityRecordCount = physicsCorpusAcceptedHardwareParityRecordCount
            self.physicsCorpusHardwareEvidenceRecordCount = physicsCorpusHardwareEvidenceRecordCount
            self.physicsCorpusHardwareMeasurementSystemCount = physicsCorpusHardwareMeasurementSystemCount
            self.physicsCorpusHardwareMeasurementDeviceIDCount = physicsCorpusHardwareMeasurementDeviceIDCount
            self.physicsCorpusHardwareReportHashCount = physicsCorpusHardwareReportHashCount
            self.physicsCorpusHardwareJointCalibrationRecordCount = physicsCorpusHardwareJointCalibrationRecordCount
            self.physicsCorpusMeasuredHardwareJointSampleCount = physicsCorpusMeasuredHardwareJointSampleCount
            self.physicsCorpusObservedHardwareJointSampleCount = physicsCorpusObservedHardwareJointSampleCount
            self.physicsCorpusHardwareSensorCalibrationRecordCount = physicsCorpusHardwareSensorCalibrationRecordCount
            self.physicsCorpusObservedHardwareSensorSampleCount = physicsCorpusObservedHardwareSensorSampleCount
            self.physicsCorpusContactReplayRecordCount = physicsCorpusContactReplayRecordCount
            self.referenceM2StressCoverageComplete = referenceM2StressCoverageComplete
            self.observabilityArtifactCount = observabilityArtifactCount
            self.observabilitySampleCount = observabilitySampleCount
            self.stressSuiteCount = stressSuiteCount
            self.stressScenarioRecordCount = stressScenarioRecordCount
            self.datasetRecordCount = datasetRecordCount
            self.datasetCount = datasetCount
            self.curriculumStageCount = curriculumStageCount
            self.createdAt = createdAt
        }

        public static func < (lhs: Score, rhs: Score) -> Bool {
            if lhs.checkpointRank != rhs.checkpointRank {
                return lhs.checkpointRank < rhs.checkpointRank
            }
            if lhs.acceptedRegressionArtifactCount != rhs.acceptedRegressionArtifactCount {
                return lhs.acceptedRegressionArtifactCount < rhs.acceptedRegressionArtifactCount
            }
            if lhs.totalRegressionArtifactCount != rhs.totalRegressionArtifactCount {
                return lhs.totalRegressionArtifactCount < rhs.totalRegressionArtifactCount
            }
            if lhs.physicsCorpusCount != rhs.physicsCorpusCount {
                return lhs.physicsCorpusCount < rhs.physicsCorpusCount
            }
            if lhs.physicsCorpusAcceptedRecordCount != rhs.physicsCorpusAcceptedRecordCount {
                return lhs.physicsCorpusAcceptedRecordCount < rhs.physicsCorpusAcceptedRecordCount
            }
            if lhs.physicsCorpusAcceptedHardwareParityRecordCount
                != rhs.physicsCorpusAcceptedHardwareParityRecordCount {
                return lhs.physicsCorpusAcceptedHardwareParityRecordCount
                    < rhs.physicsCorpusAcceptedHardwareParityRecordCount
            }
            if lhs.physicsCorpusHardwareEvidenceRecordCount != rhs.physicsCorpusHardwareEvidenceRecordCount {
                return lhs.physicsCorpusHardwareEvidenceRecordCount < rhs.physicsCorpusHardwareEvidenceRecordCount
            }
            if lhs.physicsCorpusHardwareMeasurementSystemCount != rhs.physicsCorpusHardwareMeasurementSystemCount {
                return lhs.physicsCorpusHardwareMeasurementSystemCount < rhs.physicsCorpusHardwareMeasurementSystemCount
            }
            if lhs.physicsCorpusHardwareMeasurementDeviceIDCount != rhs.physicsCorpusHardwareMeasurementDeviceIDCount {
                return lhs.physicsCorpusHardwareMeasurementDeviceIDCount < rhs.physicsCorpusHardwareMeasurementDeviceIDCount
            }
            if lhs.physicsCorpusHardwareReportHashCount != rhs.physicsCorpusHardwareReportHashCount {
                return lhs.physicsCorpusHardwareReportHashCount < rhs.physicsCorpusHardwareReportHashCount
            }
            if lhs.physicsCorpusHardwareJointCalibrationRecordCount
                != rhs.physicsCorpusHardwareJointCalibrationRecordCount {
                return lhs.physicsCorpusHardwareJointCalibrationRecordCount
                    < rhs.physicsCorpusHardwareJointCalibrationRecordCount
            }
            if lhs.physicsCorpusMeasuredHardwareJointSampleCount != rhs.physicsCorpusMeasuredHardwareJointSampleCount {
                return lhs.physicsCorpusMeasuredHardwareJointSampleCount
                    < rhs.physicsCorpusMeasuredHardwareJointSampleCount
            }
            if lhs.physicsCorpusObservedHardwareJointSampleCount != rhs.physicsCorpusObservedHardwareJointSampleCount {
                return lhs.physicsCorpusObservedHardwareJointSampleCount
                    < rhs.physicsCorpusObservedHardwareJointSampleCount
            }
            if lhs.physicsCorpusHardwareSensorCalibrationRecordCount
                != rhs.physicsCorpusHardwareSensorCalibrationRecordCount {
                return lhs.physicsCorpusHardwareSensorCalibrationRecordCount
                    < rhs.physicsCorpusHardwareSensorCalibrationRecordCount
            }
            if lhs.physicsCorpusObservedHardwareSensorSampleCount
                != rhs.physicsCorpusObservedHardwareSensorSampleCount {
                return lhs.physicsCorpusObservedHardwareSensorSampleCount
                    < rhs.physicsCorpusObservedHardwareSensorSampleCount
            }
            if lhs.physicsCorpusContactReplayRecordCount != rhs.physicsCorpusContactReplayRecordCount {
                return lhs.physicsCorpusContactReplayRecordCount < rhs.physicsCorpusContactReplayRecordCount
            }
            if lhs.referenceM2StressCoverageComplete != rhs.referenceM2StressCoverageComplete {
                return !lhs.referenceM2StressCoverageComplete && rhs.referenceM2StressCoverageComplete
            }
            if lhs.observabilityArtifactCount != rhs.observabilityArtifactCount {
                return lhs.observabilityArtifactCount < rhs.observabilityArtifactCount
            }
            if lhs.observabilitySampleCount != rhs.observabilitySampleCount {
                return lhs.observabilitySampleCount < rhs.observabilitySampleCount
            }
            if lhs.stressSuiteCount != rhs.stressSuiteCount {
                return lhs.stressSuiteCount < rhs.stressSuiteCount
            }
            if lhs.stressScenarioRecordCount != rhs.stressScenarioRecordCount {
                return lhs.stressScenarioRecordCount < rhs.stressScenarioRecordCount
            }
            if lhs.datasetRecordCount != rhs.datasetRecordCount {
                return lhs.datasetRecordCount < rhs.datasetRecordCount
            }
            if lhs.datasetCount != rhs.datasetCount {
                return lhs.datasetCount < rhs.datasetCount
            }
            if lhs.curriculumStageCount != rhs.curriculumStageCount {
                return lhs.curriculumStageCount < rhs.curriculumStageCount
            }
            return lhs.createdAt < rhs.createdAt
        }

        private enum CodingKeys: String, CodingKey {
            case checkpointState
            case checkpointRank
            case acceptedRegressionArtifactCount
            case totalRegressionArtifactCount
            case physicsCorpusCount
            case physicsCorpusAcceptedRecordCount
            case physicsCorpusAcceptedHardwareParityRecordCount
            case physicsCorpusHardwareEvidenceRecordCount
            case physicsCorpusHardwareMeasurementSystemCount
            case physicsCorpusHardwareMeasurementDeviceIDCount
            case physicsCorpusHardwareReportHashCount
            case physicsCorpusHardwareJointCalibrationRecordCount
            case physicsCorpusMeasuredHardwareJointSampleCount
            case physicsCorpusObservedHardwareJointSampleCount
            case physicsCorpusHardwareSensorCalibrationRecordCount
            case physicsCorpusObservedHardwareSensorSampleCount
            case physicsCorpusContactReplayRecordCount
            case referenceM2StressCoverageComplete
            case observabilityArtifactCount
            case observabilitySampleCount
            case stressSuiteCount
            case stressScenarioRecordCount
            case datasetRecordCount
            case datasetCount
            case curriculumStageCount
            case createdAt
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                checkpointState: try container.decode(CheckpointDecisionState.self, forKey: .checkpointState),
                checkpointRank: try container.decode(Int.self, forKey: .checkpointRank),
                acceptedRegressionArtifactCount: try container.decode(
                    Int.self,
                    forKey: .acceptedRegressionArtifactCount
                ),
                totalRegressionArtifactCount: try container.decode(Int.self, forKey: .totalRegressionArtifactCount),
                physicsCorpusCount: try container.decode(Int.self, forKey: .physicsCorpusCount),
                physicsCorpusAcceptedRecordCount: try container.decode(
                    Int.self,
                    forKey: .physicsCorpusAcceptedRecordCount
                ),
                physicsCorpusAcceptedHardwareParityRecordCount: try container.decodeIfPresent(
                    Int.self,
                    forKey: .physicsCorpusAcceptedHardwareParityRecordCount
                ) ?? 0,
                physicsCorpusHardwareEvidenceRecordCount: try container.decodeIfPresent(
                    Int.self,
                    forKey: .physicsCorpusHardwareEvidenceRecordCount
                ) ?? 0,
                physicsCorpusHardwareMeasurementSystemCount: try container.decodeIfPresent(
                    Int.self,
                    forKey: .physicsCorpusHardwareMeasurementSystemCount
                ) ?? 0,
                physicsCorpusHardwareMeasurementDeviceIDCount: try container.decodeIfPresent(
                    Int.self,
                    forKey: .physicsCorpusHardwareMeasurementDeviceIDCount
                ) ?? 0,
                physicsCorpusHardwareReportHashCount: try container.decodeIfPresent(
                    Int.self,
                    forKey: .physicsCorpusHardwareReportHashCount
                ) ?? 0,
                physicsCorpusHardwareJointCalibrationRecordCount: try container.decodeIfPresent(
                    Int.self,
                    forKey: .physicsCorpusHardwareJointCalibrationRecordCount
                ) ?? 0,
                physicsCorpusMeasuredHardwareJointSampleCount: try container.decodeIfPresent(
                    Int.self,
                    forKey: .physicsCorpusMeasuredHardwareJointSampleCount
                ) ?? 0,
                physicsCorpusObservedHardwareJointSampleCount: try container.decodeIfPresent(
                    Int.self,
                    forKey: .physicsCorpusObservedHardwareJointSampleCount
                ) ?? 0,
                physicsCorpusHardwareSensorCalibrationRecordCount: try container.decodeIfPresent(
                    Int.self,
                    forKey: .physicsCorpusHardwareSensorCalibrationRecordCount
                ) ?? 0,
                physicsCorpusObservedHardwareSensorSampleCount: try container.decodeIfPresent(
                    Int.self,
                    forKey: .physicsCorpusObservedHardwareSensorSampleCount
                ) ?? 0,
                physicsCorpusContactReplayRecordCount: try container.decodeIfPresent(
                    Int.self,
                    forKey: .physicsCorpusContactReplayRecordCount
                ) ?? 0,
                referenceM2StressCoverageComplete: try container.decode(
                    Bool.self,
                    forKey: .referenceM2StressCoverageComplete
                ),
                observabilityArtifactCount: try container.decode(Int.self, forKey: .observabilityArtifactCount),
                observabilitySampleCount: try container.decode(Int.self, forKey: .observabilitySampleCount),
                stressSuiteCount: try container.decode(Int.self, forKey: .stressSuiteCount),
                stressScenarioRecordCount: try container.decode(Int.self, forKey: .stressScenarioRecordCount),
                datasetRecordCount: try container.decode(Int.self, forKey: .datasetRecordCount),
                datasetCount: try container.decode(Int.self, forKey: .datasetCount),
                curriculumStageCount: try container.decode(Int.self, forKey: .curriculumStageCount),
                createdAt: try container.decode(Date.self, forKey: .createdAt)
            )
        }
    }

    public let incumbentProjectID: String
    public let candidateProjectID: String
    public let decision: Decision
    public let dominantFactor: DominantFactor
    public let incumbentScore: Score
    public let candidateScore: Score

    public init(
        incumbentProjectID: String,
        candidateProjectID: String,
        decision: Decision,
        dominantFactor: DominantFactor,
        incumbentScore: Score,
        candidateScore: Score
    ) {
        self.incumbentProjectID = incumbentProjectID
        self.candidateProjectID = candidateProjectID
        self.decision = decision
        self.dominantFactor = dominantFactor
        self.incumbentScore = incumbentScore
        self.candidateScore = candidateScore
    }
}
