import KuyuTrainingContracts

public struct TrainingRunWorkerTerminalSummaryResolver: Sendable {
  public init() {}

  public func resolvedSummary(_ summary: TrainingRunSummary) -> TrainingRunSummary {
    guard TrainingRunWorkerProcessDisposition(summary: summary) == .invalidOutcome else {
      return summary
    }
    let reason: String
    switch summary.terminalState {
    case .completed:
      reason = "training worker completed without an accepted checkpoint"
    case .running:
      reason = "training worker returned a non-terminal running summary"
    case .cancelled, .failed, .rejected:
      reason = "training worker returned an inconsistent terminal summary"
    }
    return TrainingRunSummary(
      runID: summary.runID,
      artifactRoot: summary.artifactRoot,
      terminalState: .failed,
      generationCount: summary.generationCount,
      candidateCount: summary.candidateCount,
      failureReasons: summary.failureReasons + [reason]
    )
  }
}
