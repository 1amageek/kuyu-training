public enum TrainingRunWorkerProcessDisposition: String, Sendable, Codable, Equatable {
  case success
  case rejection
  case cancellation
  case failure
  case invalidOutcome

  public init(
    terminalState: TrainingRunTerminalState,
    hasAcceptedCheckpoint: Bool
  ) {
    switch terminalState {
    case .completed where hasAcceptedCheckpoint:
      self = .success
    case .cancelled:
      self = .cancellation
    case .rejected:
      self = .rejection
    case .failed:
      self = .failure
    case .running, .completed:
      self = .invalidOutcome
    }
  }

  public init(summary: TrainingRunSummary) {
    self.init(
      terminalState: summary.terminalState,
      hasAcceptedCheckpoint: summary.acceptedCheckpoint != nil
    )
  }

  public var exitStatus: Int32 {
    acceptedExitStatuses[0]
  }

  public var acceptedExitStatuses: [Int32] {
    switch self {
    case .success:
      [0]
    case .rejection:
      [64]
    case .cancellation:
      [130, 143]
    case .failure, .invalidOutcome:
      [1]
    }
  }

  public func accepts(exitStatus: Int32) -> Bool {
    acceptedExitStatuses.contains(exitStatus)
  }
}
