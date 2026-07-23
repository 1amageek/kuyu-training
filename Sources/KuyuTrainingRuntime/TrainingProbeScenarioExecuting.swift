import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public protocol TrainingProbeScenarioExecuting: Sendable {
    func runProbeSuite(
        stage: TrainingProbeStage,
        request: SimulationRunRequest,
        checkpointURL: URL?
    ) async throws -> TrainingScenarioRunOutput

    func writeRecoveryRelabelDataset(
        output: TrainingScenarioRunOutput,
        request: SimulationRunRequest,
        to directory: URL,
        includeSuccessfulScenarios: Bool
    ) async throws -> RecoveryRelabelReport?
}

public extension TrainingProbeScenarioExecuting {
    func writeRecoveryRelabelDataset(
        output: TrainingScenarioRunOutput,
        request: SimulationRunRequest,
        to directory: URL,
        includeSuccessfulScenarios: Bool
    ) async throws -> RecoveryRelabelReport? {
        _ = includeSuccessfulScenarios
        return nil
    }
}
