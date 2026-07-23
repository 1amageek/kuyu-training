import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public enum TrainingProbeStage: String, Sendable, Codable, Equatable {
    case teacherActiveAltitudeHold
    case initialPolicy
    case trainingIteration
    case trainingProgress
    case trainedPolicy
}
