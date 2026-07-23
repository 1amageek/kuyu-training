import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

extension TrainingProbeOrchestrator {
    func failedResult(
        manifest: TrainingProbeManifest,
        teacher: TrainingProbeRunSummary?,
        initial: TrainingProbeRunSummary?,
        trainingConfig: TrainingRunConfig,
        artifactDirectory: URL,
        reason: String
    ) async -> TrainingProbeResult {
        let training = emptyTrainingResult(runID: trainingConfig.runID, reason: reason)
        return await failedResult(
            manifest: manifest,
            teacher: teacher,
            initial: initial,
            training: training,
            artifactDirectory: artifactDirectory,
            reason: reason
        )
    }

    func failedResult(
        manifest: TrainingProbeManifest,
        teacher: TrainingProbeRunSummary?,
        initial: TrainingProbeRunSummary?,
        training: TrainingRunResult,
        artifactDirectory: URL,
        reason: String
    ) async -> TrainingProbeResult {
        let fallbackTeacher = teacher ?? TrainingProbeRunSummary.empty(stage: .teacherActiveAltitudeHold)
        let fallbackInitial = initial ?? TrainingProbeRunSummary.empty(stage: .initialPolicy)
        let comparison = TrainingProbeComparison(
            probeID: manifest.probeID,
            trainingRunID: manifest.trainingRunID,
            teacher: fallbackTeacher,
            initial: fallbackInitial,
            trained: nil,
            training: training,
            minScoreDelta: manifest.minScoreDelta,
            requireTeacherPass: manifest.requireTeacherPass,
            requireTrainedPass: manifest.requireTrainedPass,
            sourceCheckpointURL: manifest.sourceCheckpointURL
        )
        let probeCheckpointDecision = CheckpointDecision(
            runID: training.manifest.runID,
            state: .skipped,
            reason: reason,
            candidateCheckpointID: training.checkpointDecision.candidateCheckpointID,
            candidateCheckpointURL: training.checkpointDecision.candidateCheckpointURL,
            publishedCheckpointURL: nil
        )
        let failedManifest = manifest.completed(at: Date(), terminalState: .failed, failureReason: reason)
        let result = TrainingProbeResult(
            manifest: failedManifest,
            teacher: fallbackTeacher,
            initial: fallbackInitial,
            training: training,
            trained: nil,
            comparison: comparison,
            probeCheckpointDecision: probeCheckpointDecision
        )
        do {
            try artifactWriter.write(result: result, to: artifactDirectory)
        } catch {
            return TrainingProbeResult(
                manifest: failedManifest.completed(
                    at: Date(),
                    terminalState: .failed,
                    failureReason: "probe-artifact-write-failed: \(error)"
                ),
                teacher: fallbackTeacher,
                initial: fallbackInitial,
                training: training,
                trained: nil,
                comparison: comparison,
                probeCheckpointDecision: probeCheckpointDecision
            )
        }
        return result
    }

    private func emptyTrainingResult(runID: String, reason: String) -> TrainingRunResult {
        let convergence = ConvergenceSummary(
            runID: runID,
            accepted: false,
            reason: reason,
            passRate: 0,
            failureRate: 1,
            safetyRegressionDetected: false,
            plateauDetected: false,
            overfitRiskDetected: false
        )
        return TrainingRunResult(
            manifest: LearningRunManifest(
                runID: runID,
                mode: .supervised,
                configHash: "probe-unstarted",
                suiteID: "probe",
                seedSet: [],
                policyID: "probe",
                workerCount: 1,
                startedAt: Date(),
                completedAt: Date(),
                terminalState: .failed,
                failureReason: reason
            ),
            metrics: [],
            convergence: convergence,
            checkpointDecision: CheckpointDecision(
                runID: runID,
                state: .skipped,
                reason: reason,
                candidateCheckpointID: nil,
                candidateCheckpointURL: nil,
                publishedCheckpointURL: nil
            )
        )
    }
}
