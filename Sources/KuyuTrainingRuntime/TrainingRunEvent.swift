import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public enum TrainingRunEvent: Sendable, Equatable {
    case started(LearningRunManifest)
    case progress(TrainingRunProgressEvent)
    case log(TrainingRunLogEvent)
    case iterationStarted(Int)
    case suiteCompleted(iteration: Int, output: TrainingScenarioRunOutput, score: Double)
    case datasetExported(iteration: Int, directory: String, count: Int)
    case trainingCompleted(iteration: Int, result: TrainingBackendResult)
    case reinforcementTrainingCompleted(iteration: Int, result: ReinforcementTrainingBackendResult)
    case convergenceUpdated(ConvergenceSummary)
    case completed(TrainingRunResult)
}
