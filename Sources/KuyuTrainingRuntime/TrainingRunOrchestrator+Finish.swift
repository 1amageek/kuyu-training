import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

extension TrainingRunOrchestrator {
    func finish(
        manifest: LearningRunManifest,
        metrics: [TrainingMetricRecord],
        bestCheckpointID: String?,
        bestCheckpointURL: URL?,
        finalCheckpointID: String?,
        finalCheckpointURL: URL?,
        scenarioRuns: [TrainingScenarioRunArtifact] = [],
        artifactDirectory: URL,
        state: LearningRunTerminalState,
        failureReason: String?,
        onEvent: (@Sendable (TrainingRunEvent) -> Void)?
    ) async -> TrainingRunResult {
        let convergence = convergenceEvaluator.evaluate(
            runID: manifest.runID,
            metrics: metrics,
            bestCheckpointID: bestCheckpointID ?? finalCheckpointID
        )
        return await finish(
            manifest: manifest,
            metrics: metrics,
            convergence: ConvergenceSummary(
                runID: convergence.runID,
                accepted: false,
                reason: failureReason ?? convergence.reason,
                bestCheckpointID: convergence.bestCheckpointID,
                finalTrainingLoss: convergence.finalTrainingLoss,
                finalValidationLoss: convergence.finalValidationLoss,
                rewardMovingAverage: convergence.rewardMovingAverage,
                passRate: convergence.passRate,
                failureRate: convergence.failureRate,
                safetyRegressionDetected: convergence.safetyRegressionDetected,
                plateauDetected: convergence.plateauDetected,
                overfitRiskDetected: convergence.overfitRiskDetected
            ),
            finalCheckpointID: finalCheckpointID,
            finalCheckpointURL: finalCheckpointURL,
            scenarioRuns: scenarioRuns,
            artifactDirectory: artifactDirectory,
            checkpointPublicationMode: .immediate,
            state: state,
            failureReason: failureReason,
            onEvent: onEvent
        )
    }

    func finish(
        manifest: LearningRunManifest,
        metrics: [TrainingMetricRecord],
        convergence: ConvergenceSummary,
        finalCheckpointID: String?,
        finalCheckpointURL: URL?,
        scenarioRuns: [TrainingScenarioRunArtifact],
        artifactDirectory: URL,
        checkpointPublicationMode: TrainingRunConfig.CheckpointPublicationMode,
        state: LearningRunTerminalState,
        failureReason: String?,
        onEvent: (@Sendable (TrainingRunEvent) -> Void)?
    ) async -> TrainingRunResult {
        let checkpointDecision = finalizeCheckpointDecision(
            runID: manifest.runID,
            convergence: convergence,
            candidateCheckpointID: finalCheckpointID,
            candidateCheckpointURL: finalCheckpointURL,
            artifactDirectory: artifactDirectory,
            publicationMode: checkpointPublicationMode
        )
        let completedManifest = manifest.completed(
            at: Date(),
            terminalState: state,
            outputCheckpointID: finalCheckpointID,
            failureReason: failureReason
        )
        do {
            try artifactWriter.write(
                manifest: completedManifest,
                metrics: metrics,
                convergence: convergence,
                checkpointDecision: checkpointDecision,
                scenarioRuns: scenarioRuns,
                to: artifactDirectory
            )
        } catch {
            // Artifact failures are reflected in the returned manifest but do not erase the run outcome.
            let artifactFailureManifest = completedManifest.completed(
                at: Date(),
                terminalState: .failed,
                outputCheckpointID: finalCheckpointID,
                failureReason: "artifact-write-failed: \(error)"
            )
            let result = TrainingRunResult(
                manifest: artifactFailureManifest,
                metrics: metrics,
                convergence: convergence,
                checkpointDecision: checkpointDecision
            )
            onEvent?(.completed(result))
            return result
        }

        let result = TrainingRunResult(
            manifest: completedManifest,
            metrics: metrics,
            convergence: convergence,
            checkpointDecision: checkpointDecision
        )
        onEvent?(.completed(result))
        return result
    }

    private func finalizeCheckpointDecision(
        runID: String,
        convergence: ConvergenceSummary,
        candidateCheckpointID: String?,
        candidateCheckpointURL: URL?,
        artifactDirectory: URL,
        publicationMode: TrainingRunConfig.CheckpointPublicationMode
    ) -> CheckpointDecision {
        let initial = checkpointPolicy.decision(
            runID: runID,
            convergence: convergence,
            candidateCheckpointID: candidateCheckpointID,
            candidateCheckpointURL: candidateCheckpointURL
        )
        if publicationMode == .deferred, initial.state == .accepted {
            return CheckpointDecision(
                runID: runID,
                state: .staged,
                reason: "checkpoint-publication-deferred",
                candidateCheckpointID: candidateCheckpointID,
                candidateCheckpointURL: candidateCheckpointURL,
                publishedCheckpointURL: nil,
                decidedAt: initial.decidedAt
            )
        }
        do {
            return try checkpointRepository.publish(decision: initial, under: artifactDirectory)
        } catch {
            return CheckpointDecision(
                runID: runID,
                state: .failed,
                reason: "checkpoint-publish-failed: \(error)",
                candidateCheckpointID: candidateCheckpointID,
                candidateCheckpointURL: candidateCheckpointURL
            )
        }
    }
}
