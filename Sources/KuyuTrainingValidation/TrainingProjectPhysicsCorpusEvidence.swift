import KuyuPhysics

public struct TrainingProjectPhysicsCorpusEvidence: Sendable, Codable, Equatable {
    public let corpusID: String
    public let acceptedRecordCount: Int
    public let hardwareParityGapCount: Int
    public let requiredReadinessLevels: [ReadinessLevel]
    public let hardwareEvidenceRecordCount: Int
    public let acceptedHardwareParityRecordCount: Int
    public let hardwareEvidenceReportHashes: [String]
    public let hardwareEvidenceMeasurementSystems: [String]
    public let hardwareEvidenceDeviceIDs: [String]
    public let hardwareJointCalibrationRecordCount: Int
    public let hardwareJointSampleCount: Int
    public let measuredHardwareJointSampleCount: Int
    public let observedHardwareJointSampleCount: Int
    public let hardwareSensorCalibrationRecordCount: Int
    public let hardwareSensorSampleCount: Int
    public let observedHardwareSensorSampleCount: Int
    public let contactReplayRecordCount: Int
    public let path: String

    private enum CodingKeys: String, CodingKey {
        case corpusID
        case acceptedRecordCount
        case hardwareParityGapCount
        case requiredReadinessLevels
        case hardwareEvidenceRecordCount
        case acceptedHardwareParityRecordCount
        case hardwareEvidenceReportHashes
        case hardwareEvidenceMeasurementSystems
        case hardwareEvidenceDeviceIDs
        case hardwareJointCalibrationRecordCount
        case hardwareJointSampleCount
        case measuredHardwareJointSampleCount
        case observedHardwareJointSampleCount
        case hardwareSensorCalibrationRecordCount
        case hardwareSensorSampleCount
        case observedHardwareSensorSampleCount
        case contactReplayRecordCount
        case path
    }

    public init(
        corpusID: String,
        acceptedRecordCount: Int,
        hardwareParityGapCount: Int,
        requiredReadinessLevels: [ReadinessLevel],
        hardwareEvidenceRecordCount: Int = 0,
        acceptedHardwareParityRecordCount: Int = 0,
        hardwareEvidenceReportHashes: [String] = [],
        hardwareEvidenceMeasurementSystems: [String] = [],
        hardwareEvidenceDeviceIDs: [String] = [],
        hardwareJointCalibrationRecordCount: Int = 0,
        hardwareJointSampleCount: Int = 0,
        measuredHardwareJointSampleCount: Int = 0,
        observedHardwareJointSampleCount: Int = 0,
        hardwareSensorCalibrationRecordCount: Int = 0,
        hardwareSensorSampleCount: Int = 0,
        observedHardwareSensorSampleCount: Int = 0,
        contactReplayRecordCount: Int = 0,
        path: String
    ) {
        self.corpusID = corpusID
        self.acceptedRecordCount = acceptedRecordCount
        self.hardwareParityGapCount = hardwareParityGapCount
        self.requiredReadinessLevels = requiredReadinessLevels
        self.hardwareEvidenceRecordCount = hardwareEvidenceRecordCount
        self.acceptedHardwareParityRecordCount = acceptedHardwareParityRecordCount
        self.hardwareEvidenceReportHashes = hardwareEvidenceReportHashes
        self.hardwareEvidenceMeasurementSystems = hardwareEvidenceMeasurementSystems
        self.hardwareEvidenceDeviceIDs = hardwareEvidenceDeviceIDs
        self.hardwareJointCalibrationRecordCount = hardwareJointCalibrationRecordCount
        self.hardwareJointSampleCount = hardwareJointSampleCount
        self.measuredHardwareJointSampleCount = measuredHardwareJointSampleCount
        self.observedHardwareJointSampleCount = observedHardwareJointSampleCount
        self.hardwareSensorCalibrationRecordCount = hardwareSensorCalibrationRecordCount
        self.hardwareSensorSampleCount = hardwareSensorSampleCount
        self.observedHardwareSensorSampleCount = observedHardwareSensorSampleCount
        self.contactReplayRecordCount = contactReplayRecordCount
        self.path = path
    }

    public init(summary: DescriptorCorpusAcceptanceSummary, path: String) {
        let sortedLevels = summary.records.map(\.requiredReadiness).sorted()
        let hardwareEvidence = summary.records.compactMap(\.hardwareEvidence)
        let reportHashes = Set(hardwareEvidence.map(\.reportHash)).sorted()
        let measurementSystems = Set(hardwareEvidence.map(\.measurementSystem)).sorted()
        let deviceIDs = Set(hardwareEvidence.compactMap(\.deviceID)).sorted()
        let jointCalibrationRecordCount = hardwareEvidence.filter { $0.jointCalibrationCount > 0 }.count
        let sensorCalibrationRecordCount = hardwareEvidence.filter { $0.sensorCalibrationCount > 0 }.count
        self.init(
            corpusID: summary.corpusID,
            acceptedRecordCount: summary.records.filter(\.accepted).count,
            hardwareParityGapCount: summary.hardwareParityGaps.count,
            requiredReadinessLevels: sortedLevels.reduce(into: []) { uniqueLevels, level in
                guard !uniqueLevels.contains(level) else { return }
                uniqueLevels.append(level)
            },
            hardwareEvidenceRecordCount: hardwareEvidence.count,
            acceptedHardwareParityRecordCount: summary.records.filter { $0.hardwareParity == .accepted }.count,
            hardwareEvidenceReportHashes: reportHashes,
            hardwareEvidenceMeasurementSystems: measurementSystems,
            hardwareEvidenceDeviceIDs: deviceIDs,
            hardwareJointCalibrationRecordCount: jointCalibrationRecordCount,
            hardwareJointSampleCount: hardwareEvidence.reduce(0) { $0 + $1.jointSampleCount },
            measuredHardwareJointSampleCount: hardwareEvidence.reduce(0) { $0 + $1.measuredJointSampleCount },
            observedHardwareJointSampleCount: hardwareEvidence.reduce(0) { partial, evidence in
                partial + (evidence.observedJointSampleCount ?? 0)
            },
            hardwareSensorCalibrationRecordCount: sensorCalibrationRecordCount,
            hardwareSensorSampleCount: hardwareEvidence.reduce(0) { $0 + $1.sensorSampleCount },
            observedHardwareSensorSampleCount: hardwareEvidence.reduce(0) { $0 + $1.observedSensorSampleCount },
            contactReplayRecordCount: summary.records.filter { $0.replay.contact != nil }.count,
            path: path
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            corpusID: try container.decode(String.self, forKey: .corpusID),
            acceptedRecordCount: try container.decode(Int.self, forKey: .acceptedRecordCount),
            hardwareParityGapCount: try container.decode(Int.self, forKey: .hardwareParityGapCount),
            requiredReadinessLevels: try container.decode(
                [ReadinessLevel].self,
                forKey: .requiredReadinessLevels
            ),
            hardwareEvidenceRecordCount: try container.decodeIfPresent(
                Int.self,
                forKey: .hardwareEvidenceRecordCount
            ) ?? 0,
            acceptedHardwareParityRecordCount: try container.decodeIfPresent(
                Int.self,
                forKey: .acceptedHardwareParityRecordCount
            ) ?? 0,
            hardwareEvidenceReportHashes: try container.decodeIfPresent(
                [String].self,
                forKey: .hardwareEvidenceReportHashes
            ) ?? [],
            hardwareEvidenceMeasurementSystems: try container.decodeIfPresent(
                [String].self,
                forKey: .hardwareEvidenceMeasurementSystems
            ) ?? [],
            hardwareEvidenceDeviceIDs: try container.decodeIfPresent(
                [String].self,
                forKey: .hardwareEvidenceDeviceIDs
            ) ?? [],
            hardwareJointCalibrationRecordCount: try container.decodeIfPresent(
                Int.self,
                forKey: .hardwareJointCalibrationRecordCount
            ) ?? 0,
            hardwareJointSampleCount: try container.decodeIfPresent(
                Int.self,
                forKey: .hardwareJointSampleCount
            ) ?? 0,
            measuredHardwareJointSampleCount: try container.decodeIfPresent(
                Int.self,
                forKey: .measuredHardwareJointSampleCount
            ) ?? 0,
            observedHardwareJointSampleCount: try container.decodeIfPresent(
                Int.self,
                forKey: .observedHardwareJointSampleCount
            ) ?? 0,
            hardwareSensorCalibrationRecordCount: try container.decodeIfPresent(
                Int.self,
                forKey: .hardwareSensorCalibrationRecordCount
            ) ?? 0,
            hardwareSensorSampleCount: try container.decodeIfPresent(
                Int.self,
                forKey: .hardwareSensorSampleCount
            ) ?? 0,
            observedHardwareSensorSampleCount: try container.decodeIfPresent(
                Int.self,
                forKey: .observedHardwareSensorSampleCount
            ) ?? 0,
            contactReplayRecordCount: try container.decodeIfPresent(
                Int.self,
                forKey: .contactReplayRecordCount
            ) ?? 0,
            path: try container.decode(String.self, forKey: .path)
        )
    }
}
