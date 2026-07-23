import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public struct TrainingProbeResult: Sendable, Equatable {
    public let manifest: TrainingProbeManifest
    public let teacher: TrainingProbeRunSummary
    public let initial: TrainingProbeRunSummary
    public let training: TrainingRunResult
    public let trained: TrainingProbeRunSummary?
    public let comparison: TrainingProbeComparison
    public let probeCheckpointDecision: CheckpointDecision
    public let recoveryRelabelStatus: TrainingProbeRecoveryRelabelStatus

    public init(
        manifest: TrainingProbeManifest,
        teacher: TrainingProbeRunSummary,
        initial: TrainingProbeRunSummary,
        training: TrainingRunResult,
        trained: TrainingProbeRunSummary?,
        comparison: TrainingProbeComparison,
        probeCheckpointDecision: CheckpointDecision,
        recoveryRelabelStatus: TrainingProbeRecoveryRelabelStatus = .skipped(reason: "not-requested")
    ) {
        self.manifest = manifest
        self.teacher = teacher
        self.initial = initial
        self.training = training
        self.trained = trained
        self.comparison = comparison
        self.probeCheckpointDecision = probeCheckpointDecision
        self.recoveryRelabelStatus = recoveryRelabelStatus
    }
}
