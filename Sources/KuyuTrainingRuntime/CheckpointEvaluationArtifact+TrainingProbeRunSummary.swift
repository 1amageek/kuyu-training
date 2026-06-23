import Foundation
import KuyuScenarios
import KuyuTrainingValidation

public extension CheckpointEvaluationArtifact {
    init(
        evaluationID: String,
        startedAt: Date,
        profile: TaskEvaluationProfile,
        checkpointURL: URL,
        teacher: TrainingProbeRunSummary,
        policy: TrainingProbeRunSummary,
        expectedQualityKeys: [CheckpointEvaluationScenarioKey],
        qualitySummary: [ReferenceQuadrotorTaskQualitySummary],
        diagnostics: CheckpointEvaluationDiagnostics? = nil
    ) {
        self.init(
            evaluationID: evaluationID,
            startedAt: startedAt,
            task: profile.task,
            profileID: profile.profileID,
            checkpointPath: checkpointURL.path,
            teacherScore: teacher.score,
            policyScore: policy.score,
            teacherPassed: teacher.suitePassed,
            policyPassed: policy.suitePassed,
            failureReasons: policy.diagnostics.failureReasons,
            expectedQualityKeys: expectedQualityKeys,
            qualitySummary: qualitySummary,
            motorMAE: CheckpointEvaluationProbeMetrics.meanAbsoluteError(
                policy.diagnostics.averageMotorFinalOutputByIndex,
                teacher.diagnostics.averageMotorFinalOutputByIndex
            ),
            driveMAE: CheckpointEvaluationProbeMetrics.meanAbsoluteError(
                policy.diagnostics.averageDriveActivationByIndex,
                teacher.diagnostics.averageDriveActivationByIndex
            ),
            finalAltitudeDelta: CheckpointEvaluationProbeMetrics.delta(
                policy.diagnostics.finalAltitudeZ,
                teacher.diagnostics.finalAltitudeZ
            ),
            policyAverageMotorFinalOutputByIndex: policy.diagnostics.averageMotorFinalOutputByIndex,
            teacherAverageMotorFinalOutputByIndex: teacher.diagnostics.averageMotorFinalOutputByIndex,
            diagnostics: diagnostics
        )
    }
}

private enum CheckpointEvaluationProbeMetrics {
    static func meanAbsoluteError(_ lhs: [Double]?, _ rhs: [Double]?) -> Double? {
        guard let lhs, let rhs, !lhs.isEmpty, lhs.count == rhs.count else {
            return nil
        }
        return zip(lhs, rhs).reduce(0.0) { partial, pair in
            partial + abs(pair.0 - pair.1)
        } / Double(lhs.count)
    }

    static func delta(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs, let rhs else {
            return nil
        }
        return lhs - rhs
    }
}
