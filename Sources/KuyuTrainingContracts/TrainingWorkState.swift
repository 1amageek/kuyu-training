public enum TrainingWorkState: String, Codable, Sendable, Hashable {
    case started
    case advanced
    case completed
    case failed
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .started, .advanced:
            return false
        case .completed, .failed, .cancelled:
            return true
        }
    }
}
