import Foundation
import KuyuTrainingContracts
import KuyuTrainingValidation

extension TrainingProbeOrchestrator {
    func completedResult(
        manifest: TrainingProbeManifest,
        teacher: TrainingProbeRunSummary,
        initial: TrainingProbeRunSummary,
        training: TrainingRunResult,
        trained: TrainingProbeRunSummary?,
        comparison: TrainingProbeComparison,
        probeCheckpointDecision: CheckpointDecision,
        recoveryRelabelStatus: TrainingProbeRecoveryRelabelStatus,
        artifactDirectory: URL
    ) -> TrainingProbeResult {
        let outcome = terminalOutcome(
            comparison: comparison,
            checkpointDecision: probeCheckpointDecision
        )
        let completedManifest = manifest.completed(
            at: Date(),
            terminalState: outcome.state,
            failureReason: outcome.failureReason
        )
        let result = TrainingProbeResult(
            manifest: completedManifest,
            teacher: teacher,
            initial: initial,
            training: training,
            trained: trained,
            comparison: comparison,
            probeCheckpointDecision: probeCheckpointDecision,
            recoveryRelabelStatus: recoveryRelabelStatus
        )
        do {
            try artifactWriter.write(result: result, to: artifactDirectory)
            return result
        } catch {
            return TrainingProbeResult(
                manifest: completedManifest.completed(
                    at: Date(),
                    terminalState: .failed,
                    failureReason: "probe-artifact-write-failed: \(error)"
                ),
                teacher: teacher,
                initial: initial,
                training: training,
                trained: trained,
                comparison: comparison,
                probeCheckpointDecision: probeCheckpointDecision,
                recoveryRelabelStatus: recoveryRelabelStatus
            )
        }
    }

    private func terminalOutcome(
        comparison: TrainingProbeComparison,
        checkpointDecision: CheckpointDecision
    ) -> (state: LearningRunTerminalState, failureReason: String?) {
        if comparison.probeAccepted,
           checkpointDecision.state == .accepted,
           checkpointDecision.publishedCheckpointURL != nil {
            return (.completed, nil)
        }
        if comparison.probeAccepted {
            return (.failed, checkpointDecision.reason)
        }
        return (.rejected, comparison.probeRejectionReasons.joined(separator: ","))
    }
}
