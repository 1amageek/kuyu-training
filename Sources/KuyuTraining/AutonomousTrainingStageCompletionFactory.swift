import Foundation

public struct AutonomousTrainingStageCompletionFactory: Sendable {
    public init() {}

    public func reinforcementCompletion(
        stage: AutonomousTrainingStagePlan,
        bundle: TrainingRunArtifactBundle
    ) throws -> AutonomousTrainingStageCompletion {
        guard stage.kind == .reinforcement else {
            throw AutonomousTrainingStageCompletionError.stageKindUnsupported(stage.kind)
        }
        let supportedModes: [LearningRunMode] = [.rlRollout, .imaginationRL]
        guard supportedModes.contains(bundle.manifest.mode) else {
            throw AutonomousTrainingStageCompletionError.trainingRunModeMismatch(
                expected: supportedModes,
                actual: bundle.manifest.mode
            )
        }
        guard stage.taskProfileIDs.contains(bundle.manifest.suiteID) else {
            throw AutonomousTrainingStageCompletionError.trainingRunProfileMismatch(
                expected: stage.taskProfileIDs,
                actual: bundle.manifest.suiteID
            )
        }
        guard bundle.convergence.accepted else {
            throw AutonomousTrainingStageCompletionError.trainingRunNotAccepted(reason: bundle.convergence.reason)
        }
        guard bundle.checkpointDecision.state == .accepted || bundle.checkpointDecision.state == .staged else {
            throw AutonomousTrainingStageCompletionError.checkpointDecisionNotAccepted(bundle.checkpointDecision.state)
        }
        guard let checkpointURL = bundle.checkpointDecision.publishedCheckpointURL
            ?? bundle.checkpointDecision.candidateCheckpointURL else {
            throw AutonomousTrainingStageCompletionError.missingCheckpointEvidence
        }

        return AutonomousTrainingStageCompletion(
            stageID: stage.stageID,
            satisfiedGates: stage.requiredExitGates,
            evidence: [
                AutonomousTrainingStageEvidence(
                    kind: .trainingRunArtifact,
                    path: bundle.artifactDirectory.path,
                    safetyGate: .scenarioRegressionPassed
                ),
                AutonomousTrainingStageEvidence(
                    kind: .modelBundle,
                    path: checkpointURL.path,
                    safetyGate: .modelBundleValidated
                )
            ]
        )
    }
}
