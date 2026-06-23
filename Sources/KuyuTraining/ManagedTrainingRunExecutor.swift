import Foundation

/// Standard executor wrapper for managed training run lifecycles.
///
/// The supplied operations implement training semantics and emit events through
/// `TrainingRunEventEmitter`. This executor owns the public `TrainingRunHandle`
/// boundary by wrapping each operation in `ManagedTrainingRunHandle`, so callers
/// get consistent completion, cancellation, and shutdown behavior.
public struct ManagedTrainingRunExecutor: AnyTrainingRunExecuting {
    public typealias StartOperation = @Sendable (
        TrainingRunRequest,
        TrainingRunEventEmitter
    ) async throws -> TrainingRunSummary

    public typealias ResumeOperation = @Sendable (
        TrainingResumeRequest,
        TrainingRunEventEmitter
    ) async throws -> TrainingRunSummary

    private let startOperation: StartOperation
    private let resumeOperation: ResumeOperation
    private let continuationSelectionHandler: @Sendable (URL) throws -> TrainingContinuationSelection
    private let validateHandler: @Sendable (TrainingRunRequest) throws -> Void
    private let validateResumeHandler: @Sendable (TrainingResumeRequest) throws -> Void

    public init(
        start: @escaping StartOperation,
        resume: @escaping ResumeOperation,
        continuationSelection: @escaping @Sendable (URL) throws -> TrainingContinuationSelection,
        validate: @escaping @Sendable (TrainingRunRequest) throws -> Void = { _ in },
        validateResume: @escaping @Sendable (TrainingResumeRequest) throws -> Void = { _ in }
    ) {
        self.startOperation = start
        self.resumeOperation = resume
        self.continuationSelectionHandler = continuationSelection
        self.validateHandler = validate
        self.validateResumeHandler = validateResume
    }

    public func start(_ request: TrainingRunRequest) async throws -> any TrainingRunHandle {
        try validate(request)
        return ManagedTrainingRunHandle(runID: request.runID) { emitter in
            try await startOperation(request, emitter)
        }
    }

    public func resume(_ request: TrainingResumeRequest) async throws -> any TrainingRunHandle {
        try validateResumeHandler(request)
        return ManagedTrainingRunHandle(runID: request.runID) { emitter in
            try await resumeOperation(request, emitter)
        }
    }

    public func continuationSelection(from artifactRoot: URL) throws -> TrainingContinuationSelection {
        try continuationSelectionHandler(artifactRoot)
    }

    public func validate(_ request: TrainingRunRequest) throws {
        try validateHandler(request)
    }
}
