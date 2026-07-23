import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

extension TrainingRunConfig {
    func withCheckpointPublicationMode(_ mode: TrainingRunConfig.CheckpointPublicationMode) -> TrainingRunConfig {
        var copy = self
        copy.checkpointPublicationMode = mode
        return copy
    }
}
