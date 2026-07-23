import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

extension TrainingProbeOrchestrator {
    func finalizeProbeCheckpoint(
        training: TrainingRunResult,
        comparison: TrainingProbeComparison,
        trainingDirectory: URL
    ) -> CheckpointDecision {
        guard let candidateCheckpointID = training.checkpointDecision.candidateCheckpointID else {
            return CheckpointDecision(
                runID: training.manifest.runID,
                state: .skipped,
                reason: "no-candidate-checkpoint",
                candidateCheckpointID: nil,
                candidateCheckpointURL: training.checkpointDecision.candidateCheckpointURL,
                publishedCheckpointURL: nil
            )
        }
        let accepted = comparison.probeAccepted
        let initial = CheckpointDecision(
            runID: training.manifest.runID,
            state: accepted ? .accepted : .rejected,
            reason: accepted ? "probe-accepted" : "probe-rejected",
            candidateCheckpointID: candidateCheckpointID,
            candidateCheckpointURL: training.checkpointDecision.candidateCheckpointURL,
            publishedCheckpointURL: nil
        )
        do {
            return try checkpointRepository.publish(decision: initial, under: trainingDirectory)
        } catch {
            return CheckpointDecision(
                runID: training.manifest.runID,
                state: .failed,
                reason: "probe-checkpoint-publish-failed: \(error)",
                candidateCheckpointID: candidateCheckpointID,
                candidateCheckpointURL: training.checkpointDecision.candidateCheckpointURL,
                publishedCheckpointURL: nil
            )
        }
    }
}
