import Foundation
import KuyuPhysics

extension TrainingProjectEvidencePackValidator {
    func validatePhysicsCorpora(
        _ physicsCorpora: [TrainingProjectEvidencePack.PhysicsCorpusEvidence]
    ) throws {
        var corpusIDs: Set<String> = []
        var paths: Set<String> = []
        for corpus in physicsCorpora {
            let corpusID = corpus.corpusID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !corpusID.isEmpty else { throw ValidationError.emptyPhysicsCorpusID }
            guard corpusIDs.insert(corpusID).inserted else {
                throw ValidationError.duplicatePhysicsCorpusID(corpusID)
            }
            guard corpus.acceptedRecordCount > 0 else {
                throw ValidationError.invalidPhysicsCorpusAcceptedRecordCount(
                    corpusID: corpusID,
                    acceptedRecordCount: corpus.acceptedRecordCount
                )
            }
            guard corpus.hardwareParityGapCount >= 0 else {
                throw ValidationError.invalidPhysicsCorpusHardwareParityGapCount(
                    corpusID: corpusID,
                    hardwareParityGapCount: corpus.hardwareParityGapCount
                )
            }
            guard corpus.hardwareEvidenceRecordCount >= 0 else {
                throw ValidationError.invalidPhysicsCorpusHardwareEvidenceRecordCount(
                    corpusID: corpusID,
                    hardwareEvidenceRecordCount: corpus.hardwareEvidenceRecordCount
                )
            }
            guard corpus.acceptedHardwareParityRecordCount >= 0,
                  corpus.acceptedHardwareParityRecordCount <= corpus.acceptedRecordCount,
                  corpus.acceptedHardwareParityRecordCount <= corpus.hardwareEvidenceRecordCount else {
                throw ValidationError.invalidPhysicsCorpusAcceptedHardwareParityRecordCount(
                    corpusID: corpusID,
                    acceptedHardwareParityRecordCount: corpus.acceptedHardwareParityRecordCount
                )
            }
            guard corpus.hardwareJointCalibrationRecordCount >= 0,
                  corpus.hardwareJointCalibrationRecordCount <= corpus.hardwareEvidenceRecordCount else {
                throw ValidationError.invalidPhysicsCorpusHardwareJointCalibrationRecordCount(
                    corpusID: corpusID,
                    hardwareJointCalibrationRecordCount: corpus.hardwareJointCalibrationRecordCount
                )
            }
            guard corpus.hardwareJointSampleCount >= 0 else {
                throw ValidationError.invalidPhysicsCorpusHardwareJointSampleCount(
                    corpusID: corpusID,
                    hardwareJointSampleCount: corpus.hardwareJointSampleCount
                )
            }
            guard corpus.measuredHardwareJointSampleCount >= 0,
                  corpus.measuredHardwareJointSampleCount <= corpus.hardwareJointSampleCount else {
                throw ValidationError.invalidPhysicsCorpusMeasuredHardwareJointSampleCount(
                    corpusID: corpusID,
                    measuredHardwareJointSampleCount: corpus.measuredHardwareJointSampleCount
                )
            }
            guard corpus.observedHardwareJointSampleCount >= 0,
                  corpus.observedHardwareJointSampleCount <= corpus.hardwareJointSampleCount else {
                throw ValidationError.invalidPhysicsCorpusObservedHardwareJointSampleCount(
                    corpusID: corpusID,
                    observedHardwareJointSampleCount: corpus.observedHardwareJointSampleCount
                )
            }
            guard corpus.hardwareSensorCalibrationRecordCount >= 0,
                  corpus.hardwareSensorCalibrationRecordCount <= corpus.hardwareEvidenceRecordCount else {
                throw ValidationError.invalidPhysicsCorpusHardwareSensorCalibrationRecordCount(
                    corpusID: corpusID,
                    hardwareSensorCalibrationRecordCount: corpus.hardwareSensorCalibrationRecordCount
                )
            }
            guard corpus.hardwareSensorSampleCount >= 0 else {
                throw ValidationError.invalidPhysicsCorpusHardwareSensorSampleCount(
                    corpusID: corpusID,
                    hardwareSensorSampleCount: corpus.hardwareSensorSampleCount
                )
            }
            guard corpus.observedHardwareSensorSampleCount >= 0,
                  corpus.observedHardwareSensorSampleCount <= corpus.hardwareSensorSampleCount else {
                throw ValidationError.invalidPhysicsCorpusObservedHardwareSensorSampleCount(
                    corpusID: corpusID,
                    observedHardwareSensorSampleCount: corpus.observedHardwareSensorSampleCount
                )
            }
            guard corpus.contactReplayRecordCount >= 0,
                  corpus.contactReplayRecordCount <= corpus.acceptedRecordCount else {
                throw ValidationError.invalidPhysicsCorpusContactReplayRecordCount(
                    corpusID: corpusID,
                    contactReplayRecordCount: corpus.contactReplayRecordCount
                )
            }
            try validatePhysicsCorpusHardwareHashes(corpus, corpusID: corpusID)
            try validatePhysicsCorpusHardwareMeasurementProvenance(corpus, corpusID: corpusID)
            guard !corpus.requiredReadinessLevels.isEmpty else {
                throw ValidationError.emptyPhysicsCorpusReadinessLevels(corpusID)
            }
            if corpus.requiredReadinessLevels.contains(.hardwareParity) {
                guard corpus.acceptedHardwareParityRecordCount > 0,
                      corpus.hardwareEvidenceRecordCount > 0,
                      corpus.hardwareJointCalibrationRecordCount > 0,
                      corpus.measuredHardwareJointSampleCount > 0,
                      corpus.observedHardwareJointSampleCount > 0 else {
                    throw ValidationError.missingPhysicsCorpusHardwareParityEvidence(corpusID)
                }
            }
            if corpus.requiredReadinessLevels.contains(.contactTraining) {
                guard corpus.contactReplayRecordCount > 0 else {
                    throw ValidationError.missingPhysicsCorpusContactReplayEvidence(corpusID)
                }
            }
            let path = corpus.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { throw ValidationError.emptyPhysicsCorpusPath }
            guard !path.hasPrefix("/") else {
                throw ValidationError.absolutePhysicsCorpusPath(path)
            }
            let components = path.split(separator: "/").map(String.init)
            guard !components.contains("..") else {
                throw ValidationError.escapingPhysicsCorpusPath(path)
            }
            guard paths.insert(path).inserted else {
                throw ValidationError.duplicatePhysicsCorpusPath(path)
            }
        }
    }

    func validatePhysicsCorpusHardwareHashes(
        _ corpus: TrainingProjectEvidencePack.PhysicsCorpusEvidence,
        corpusID: String
    ) throws {
        var hashes: Set<String> = []
        for reportHash in corpus.hardwareEvidenceReportHashes {
            let trimmed = reportHash.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ValidationError.emptyPhysicsCorpusHardwareEvidenceReportHash(corpusID)
            }
            guard hashes.insert(trimmed).inserted else {
                throw ValidationError.duplicatePhysicsCorpusHardwareEvidenceReportHash(
                    corpusID: corpusID,
                    reportHash: trimmed
                )
            }
        }
        guard corpus.hardwareEvidenceRecordCount == 0 || !hashes.isEmpty else {
            throw ValidationError.emptyPhysicsCorpusHardwareEvidenceReportHash(corpusID)
        }
    }

    func validatePhysicsCorpusHardwareMeasurementProvenance(
        _ corpus: TrainingProjectEvidencePack.PhysicsCorpusEvidence,
        corpusID: String
    ) throws {
        var measurementSystems: Set<String> = []
        for measurementSystem in corpus.hardwareEvidenceMeasurementSystems {
            let trimmed = measurementSystem.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ValidationError.emptyPhysicsCorpusHardwareEvidenceMeasurementSystem(corpusID)
            }
            guard measurementSystems.insert(trimmed).inserted else {
                throw ValidationError.duplicatePhysicsCorpusHardwareEvidenceMeasurementSystem(
                    corpusID: corpusID,
                    measurementSystem: trimmed
                )
            }
        }
        guard corpus.hardwareEvidenceRecordCount == 0 || !measurementSystems.isEmpty else {
            throw ValidationError.emptyPhysicsCorpusHardwareEvidenceMeasurementSystem(corpusID)
        }

        var deviceIDs: Set<String> = []
        for deviceID in corpus.hardwareEvidenceDeviceIDs {
            let trimmed = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ValidationError.emptyPhysicsCorpusHardwareEvidenceDeviceID(corpusID)
            }
            guard deviceIDs.insert(trimmed).inserted else {
                throw ValidationError.duplicatePhysicsCorpusHardwareEvidenceDeviceID(
                    corpusID: corpusID,
                    deviceID: trimmed
                )
            }
        }
    }
}
