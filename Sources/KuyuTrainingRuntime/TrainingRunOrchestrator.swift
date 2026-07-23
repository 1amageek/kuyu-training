import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

@MainActor
public struct TrainingRunOrchestrator {
    public enum RunError: Error, Equatable {
        case datasetExportFailed(String)
        case backendFailed(String)
        case artifactWriteFailed(String)
    }

    public let scenarioExecutor: any TrainingScenarioExecuting
    public let scenarioEvaluator: (any TrainingScenarioEvaluating)?
    public let backend: any TrainingBackend
    public let datasetExporter: TrainingDatasetExporter
    public let artifactWriter: any MetricsWriting
    public let convergenceEvaluator: ConvergenceEvaluator
    public let checkpointPolicy: CheckpointAcceptancePolicy
    public let checkpointRepository: CheckpointRepository

    public init(
        scenarioExecutor: any TrainingScenarioExecuting,
        scenarioEvaluator: (any TrainingScenarioEvaluating)? = nil,
        backend: any TrainingBackend,
        datasetExporter: TrainingDatasetExporter = TrainingDatasetExporter(),
        artifactWriter: any MetricsWriting = TrainingArtifactWriter(),
        convergenceEvaluator: ConvergenceEvaluator = ConvergenceEvaluator(),
        checkpointPolicy: CheckpointAcceptancePolicy = CheckpointAcceptancePolicy(),
        checkpointRepository: CheckpointRepository = CheckpointRepository()
    ) {
        self.scenarioExecutor = scenarioExecutor
        self.scenarioEvaluator = scenarioEvaluator
        self.backend = backend
        self.datasetExporter = datasetExporter
        self.artifactWriter = artifactWriter
        self.convergenceEvaluator = convergenceEvaluator
        self.checkpointPolicy = checkpointPolicy
        self.checkpointRepository = checkpointRepository
    }
}
