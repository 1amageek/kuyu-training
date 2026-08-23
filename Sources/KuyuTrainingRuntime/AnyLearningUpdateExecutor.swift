import KuyuTrainingContracts

public struct AnyLearningUpdateExecutor: LearningUpdateExecuting, Sendable {
  private let executeHandler:
    @Sendable (LearningUpdateRequest) async throws -> LearningUpdateResult

  public init<Executor: LearningUpdateExecuting>(_ executor: Executor) {
    self.executeHandler = { request in
      try await executor.execute(request)
    }
  }

  public init(
    execute:
      @escaping @Sendable (LearningUpdateRequest) async throws
        -> LearningUpdateResult
  ) {
    self.executeHandler = execute
  }

  public func execute(
    _ request: LearningUpdateRequest
  ) async throws -> LearningUpdateResult {
    try await executeHandler(request)
  }
}
