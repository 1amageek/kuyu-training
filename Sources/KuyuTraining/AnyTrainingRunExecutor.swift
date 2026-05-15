public struct AnyTrainingRunExecutor: AnyTrainingRunExecuting {
    private let startHandler: @Sendable (TrainingRunRequest) async throws -> any TrainingRunHandle
    private let resumeHandler: @Sendable (TrainingResumeRequest) async throws -> any TrainingRunHandle

    public init<Executor: AnyTrainingRunExecuting>(_ executor: Executor) {
        self.startHandler = { request in
            try await executor.start(request)
        }
        self.resumeHandler = { request in
            try await executor.resume(request)
        }
    }

    public init(
        start: @escaping @Sendable (TrainingRunRequest) async throws -> any TrainingRunHandle,
        resume: @escaping @Sendable (TrainingResumeRequest) async throws -> any TrainingRunHandle
    ) {
        self.startHandler = start
        self.resumeHandler = resume
    }

    public func start(_ request: TrainingRunRequest) async throws -> any TrainingRunHandle {
        try await startHandler(request)
    }

    public func resume(_ request: TrainingResumeRequest) async throws -> any TrainingRunHandle {
        try await resumeHandler(request)
    }
}
