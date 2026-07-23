import Foundation
import KuyuScenarios
import KuyuTrainingValidation

public protocol TrainingScenarioEvaluating: Sendable {
    func runSuiteForEvaluation(
        request: SimulationRunRequest,
        checkpointURL: URL,
        scope: TrainingRunConfig.EvaluationScope
    ) async throws -> TrainingScenarioRunOutput
}
