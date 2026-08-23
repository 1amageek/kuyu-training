public protocol LearningUpdateExecuting: Sendable {
  func execute(
    _ request: LearningUpdateRequest
  ) async throws -> LearningUpdateResult
}
