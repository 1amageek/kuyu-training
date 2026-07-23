import Foundation
import KuyuTrainingContracts

public extension TrainingProbeComparison {
    func metricRecords(timestamp: Date = Date()) -> [TrainingMetricRecord] {
        var records: [TrainingMetricRecord] = []
        appendMetric(
            &records,
            kind: .scoreDelta,
            value: scoreDelta,
            step: 1,
            timestamp: timestamp
        )
        appendMetric(
            &records,
            kind: .safetyViolationDelta,
            value: safetyViolationDelta,
            step: 1,
            timestamp: timestamp
        )
        records.append(TrainingMetricRecord(
            runID: trainingRunID,
            iteration: 1,
            kind: .safetyEvidenceAvailable,
            value: safetyEvidenceAvailable ? 1.0 : 0.0,
            step: 1,
            timestamp: timestamp
        ))
        records.append(TrainingMetricRecord(
            runID: trainingRunID,
            iteration: 1,
            kind: .safetyRegression,
            value: safetyEvidenceAvailable && !safetyNonRegression ? 1.0 : 0.0,
            step: 1,
            timestamp: timestamp
        ))
        records.append(TrainingMetricRecord(
            runID: trainingRunID,
            iteration: 1,
            kind: .policySatisfied,
            value: policySatisfied ? 1.0 : 0.0,
            step: 1,
            timestamp: timestamp
        ))
        appendMetric(
            &records,
            kind: .teacherDriveAverageMAE,
            initialValue: initialTeacherDriveAverageMAE,
            trainedValue: trainedTeacherDriveAverageMAE,
            timestamp: timestamp
        )
        appendMetric(
            &records,
            kind: .teacherMotorAverageMAE,
            initialValue: initialTeacherMotorAverageMAE,
            trainedValue: trainedTeacherMotorAverageMAE,
            timestamp: timestamp
        )
        appendMetric(
            &records,
            kind: .teacherFinalAltitudeDelta,
            initialValue: initialTeacherFinalAltitudeDelta,
            trainedValue: trainedTeacherFinalAltitudeDelta,
            timestamp: timestamp
        )
        records.append(TrainingMetricRecord(
            runID: trainingRunID,
            iteration: 1,
            kind: .teacherDivergenceRegression,
            value: teacherDivergenceNonRegression ? 0.0 : 1.0,
            step: 1,
            timestamp: timestamp
        ))
        return records
    }

    private func appendMetric(
        _ records: inout [TrainingMetricRecord],
        kind: TrainingMetricKind,
        initialValue: Double?,
        trainedValue: Double?,
        timestamp: Date
    ) {
        if let initialValue {
            records.append(TrainingMetricRecord(
                runID: trainingRunID,
                iteration: 0,
                kind: kind,
                value: initialValue,
                step: 0,
                timestamp: timestamp
            ))
        }
        if let trainedValue {
            records.append(TrainingMetricRecord(
                runID: trainingRunID,
                iteration: 1,
                kind: kind,
                value: trainedValue,
                step: 1,
                timestamp: timestamp
            ))
        }
    }

    private func appendMetric(
        _ records: inout [TrainingMetricRecord],
        kind: TrainingMetricKind,
        value: Double?,
        step: Int,
        timestamp: Date
    ) {
        guard let value else {
            return
        }
        records.append(TrainingMetricRecord(
            runID: trainingRunID,
            iteration: step,
            kind: kind,
            value: value,
            step: step,
            timestamp: timestamp
        ))
    }
}
