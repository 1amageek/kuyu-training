public enum TrainingCheckpointReferenceError: Error, Sendable, Equatable {
    case pathMissing(String)
    case enumerationFailed(String)
}
