public struct TrainingRunWorkerProcessExit: Sendable, Equatable {
  public let status: Int32
  public let reason: String

  public init(status: Int32, reason: String) {
    self.status = status
    self.reason = reason
  }
}
