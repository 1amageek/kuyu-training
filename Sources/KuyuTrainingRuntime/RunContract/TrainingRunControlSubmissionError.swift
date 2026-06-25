public enum TrainingRunControlSubmissionError: Error, Sendable, Equatable, CustomStringConvertible {
    case runAlreadyFinished(runID: String, status: TrainingRunLifecycleStatus, action: TrainingRunControlAction)
    case runInterrupted(runID: String, action: TrainingRunControlAction)
    case pausedWriterDead(runID: String, action: TrainingRunControlAction)

    public var description: String {
        switch self {
        case .runAlreadyFinished(let runID, let status, let action):
            return "Run \(runID) already finished (\(status.rawValue)); \(action.rawValue) cannot be applied."
        case .runInterrupted(let runID, let action):
            return "Run \(runID) is interrupted (writer process is dead); \(action.rawValue) would never be applied."
        case .pausedWriterDead(let runID, let action):
            return "Run \(runID) is paused but its writer process is dead; \(action.rawValue) would never be applied."
        }
    }
}
