import Foundation

public enum TrainingProbeEvent: Sendable, Equatable {
    case stageStarted(TrainingProbeStage, at: Date)
    case stageCompleted(TrainingProbeRunSummary, at: Date)
    case stageFailed(TrainingProbeStage, reason: String, at: Date)
    case training(TrainingRunEvent)
}
