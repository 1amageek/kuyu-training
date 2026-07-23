import Foundation

public struct TrainingRunWorkerLaunchArtifact: Sendable, Equatable {
  public static let fileName = "training-run-worker-launch.json"

  public let launchID: UUID
  public let attemptID: UUID
  public let createdAt: Date
  public let operation: TrainingRunWorkerOperation

  public init(
    launchID: UUID = UUID(),
    attemptID: UUID = UUID(),
    createdAt: Date = Date(),
    operation: TrainingRunWorkerOperation
  ) {
    self.launchID = launchID
    self.attemptID = attemptID
    self.createdAt = Date(
      timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down)
    )
    self.operation = operation
  }
}
