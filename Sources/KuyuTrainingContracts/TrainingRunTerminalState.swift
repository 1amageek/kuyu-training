public enum TrainingRunTerminalState: String, Sendable, Codable, Equatable {
    case running
    case completed
    case failed
    case rejected
    case cancelled
}
