import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public protocol TrainingScenarioExecuting: Sendable {
    func runSuiteForTrainingRun(request: SimulationRunRequest) async throws -> TrainingScenarioRunOutput
}
