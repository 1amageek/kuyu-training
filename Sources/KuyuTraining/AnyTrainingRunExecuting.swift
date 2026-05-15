public protocol AnyTrainingRunExecuting: Sendable {
    func start(_ request: TrainingRunRequest) async throws -> any TrainingRunHandle
    func resume(_ request: TrainingResumeRequest) async throws -> any TrainingRunHandle
}
