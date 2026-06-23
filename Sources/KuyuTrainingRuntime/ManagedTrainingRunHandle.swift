import Foundation
import Synchronization
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

/// Default `TrainingRunHandle` implementation for package-owned run lifecycles.
///
/// The handle owns the event stream and guarantees that completion,
/// cancellation, shutdown, and deinitialization finish the stream exactly once.
/// Backends only receive a `TrainingRunEventEmitter`, so they cannot leak or
/// retain the underlying continuation.
public final class ManagedTrainingRunHandle: TrainingRunHandle, Sendable {
    public let runID: TrainingRunID
    public let progress: Progress
    public let events: AsyncStream<TrainingRunEvent>

    private let sink: TrainingRunEventSink
    private let task: Task<TrainingRunSummary, Error>

    public init(
        runID: TrainingRunID,
        progress: Progress = Progress(totalUnitCount: 1),
        operation: @escaping @Sendable (TrainingRunEventEmitter) async throws -> TrainingRunSummary
    ) {
        let stream = AsyncStream<TrainingRunEvent>.makeStream(
            of: TrainingRunEvent.self,
            bufferingPolicy: .unbounded
        )
        let sink = TrainingRunEventSink(continuation: stream.continuation)
        self.runID = runID
        self.progress = progress
        self.events = stream.stream
        self.sink = sink
        self.task = Task {
            let emitter = TrainingRunEventEmitter { event in
                sink.emit(event)
            }
            do {
                let summary = try await operation(emitter)
                sink.finish()
                return summary
            } catch {
                sink.finish()
                throw error
            }
        }
    }

    deinit {
        task.cancel()
        sink.finish()
    }

    public func cancel() {
        task.cancel()
        sink.finish()
    }

    public func wait() async throws -> TrainingRunSummary {
        try await task.value
    }

    public func shutdown() async {
        cancel()
    }
}

private final class TrainingRunEventSink: Sendable {
    private struct State: Sendable {
        var continuation: AsyncStream<TrainingRunEvent>.Continuation?
        var isFinished: Bool
    }

    private let state: Mutex<State>

    init(continuation: AsyncStream<TrainingRunEvent>.Continuation) {
        self.state = Mutex(State(continuation: continuation, isFinished: false))
    }

    func emit(_ event: TrainingRunEvent) {
        let continuation = state.withLock { state in
            guard !state.isFinished else {
                return nil as AsyncStream<TrainingRunEvent>.Continuation?
            }
            return state.continuation
        }
        continuation?.yield(event)
    }

    func finish() {
        let continuation = state.withLock { state in
            guard !state.isFinished else {
                return nil as AsyncStream<TrainingRunEvent>.Continuation?
            }
            state.isFinished = true
            let continuation = state.continuation
            state.continuation = nil
            return continuation
        }
        continuation?.finish()
    }
}
