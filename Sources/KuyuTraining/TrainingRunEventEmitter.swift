/// Thread-safe event emission facade passed to a managed training run.
///
/// Backends receive this value instead of owning an `AsyncStream.Continuation`
/// directly, so stream lifecycle remains centralized in `ManagedTrainingRunHandle`.
public struct TrainingRunEventEmitter: Sendable {
    private let emitHandler: @Sendable (TrainingRunEvent) -> Void

    public init(emit: @escaping @Sendable (TrainingRunEvent) -> Void) {
        self.emitHandler = emit
    }

    public func emit(_ event: TrainingRunEvent) {
        emitHandler(event)
    }
}
