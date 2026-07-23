import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

@MainActor
final class ProbeTrainingScenarioAdapter: TrainingScenarioExecuting, TrainingScenarioEvaluating {
    private let executor: any TrainingProbeScenarioExecuting
    private let checkpointURL: URL?
    private var latestEvaluation: (
        checkpointURL: URL,
        output: TrainingScenarioRunOutput,
        scope: TrainingRunConfig.EvaluationScope
    )?

    init(executor: any TrainingProbeScenarioExecuting, checkpointURL: URL?) {
        self.executor = executor
        self.checkpointURL = checkpointURL
    }

    func runSuiteForTrainingRun(request: SimulationRunRequest) async throws -> TrainingScenarioRunOutput {
        try await executor.runProbeSuite(
            stage: .trainingIteration,
            request: request,
            checkpointURL: checkpointURL
        )
    }

    func runSuiteForEvaluation(
        request: SimulationRunRequest,
        checkpointURL: URL,
        scope: TrainingRunConfig.EvaluationScope
    ) async throws -> TrainingScenarioRunOutput {
        let stage: TrainingProbeStage = scope == .progress ? .trainingProgress : .trainedPolicy
        let output = try await executor.runProbeSuite(
            stage: stage,
            request: request,
            checkpointURL: checkpointURL
        )
        latestEvaluation = (normalizedCheckpointURL(checkpointURL), output, scope)
        return output
    }

    func cachedEvaluation(
        for checkpointURL: URL,
        scope: TrainingRunConfig.EvaluationScope
    ) -> TrainingScenarioRunOutput? {
        guard latestEvaluation?.checkpointURL == normalizedCheckpointURL(checkpointURL),
              latestEvaluation?.scope == scope else {
            return nil
        }
        return latestEvaluation?.output
    }

    private func normalizedCheckpointURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
