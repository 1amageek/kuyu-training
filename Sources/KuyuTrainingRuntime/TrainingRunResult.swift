import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public struct TrainingRunResult: Sendable, Equatable {
    public let manifest: LearningRunManifest
    public let metrics: [TrainingMetricRecord]
    public let convergence: ConvergenceSummary
    public let checkpointDecision: CheckpointDecision

    public init(
        manifest: LearningRunManifest,
        metrics: [TrainingMetricRecord],
        convergence: ConvergenceSummary,
        checkpointDecision: CheckpointDecision
    ) {
        self.manifest = manifest
        self.metrics = metrics
        self.convergence = convergence
        self.checkpointDecision = checkpointDecision
    }
}
