import Foundation

public struct TrainingRunWorkerAttemptIdentity: Sendable, Codable, Equatable, Hashable {
  public let launchID: UUID
  public let attemptID: UUID
  public let launchSHA256Digest: String

  public init(
    launchID: UUID,
    attemptID: UUID,
    launchSHA256Digest: String
  ) {
    self.launchID = launchID
    self.attemptID = attemptID
    self.launchSHA256Digest = launchSHA256Digest.lowercased()
  }
}
