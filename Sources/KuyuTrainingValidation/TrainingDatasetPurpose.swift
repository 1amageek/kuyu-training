public enum TrainingDatasetPurpose: String, Sendable, Codable, Equatable {
    case behaviorCloning
    case reinforcementRollout
    case worldModel
}
