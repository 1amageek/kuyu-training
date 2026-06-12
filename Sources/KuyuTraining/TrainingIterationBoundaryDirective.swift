/// Directive returned by an iteration-boundary hook installed on
/// `TrainingRunOrchestrator.run`.
///
/// The hook runs before each iteration starts — the only point where a run
/// may be paused or stopped without tearing an iteration. `stopRun` ends the
/// loop cleanly and the run terminates as `cancelled`; a thrown error from
/// the hook terminates the run as `failed`.
public enum TrainingIterationBoundaryDirective: Sendable, Equatable {
    case continueRun
    case stopRun
}
