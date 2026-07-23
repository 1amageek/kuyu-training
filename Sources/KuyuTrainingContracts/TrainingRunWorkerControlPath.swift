import Foundation

public enum TrainingRunWorkerControlPath {
  public static let directoryName = "RUN_CONTROL"

  public static func stopSentinelURL(
    in artifactRoot: URL,
    launchID: UUID,
    attemptID: UUID
  ) -> URL {
    artifactRoot
      .appendingPathComponent(directoryName, isDirectory: true)
      .appendingPathComponent(
        stopSentinelFileName(launchID: launchID, attemptID: attemptID),
        isDirectory: false
      )
  }

  public static func stopSentinelFileName(
    launchID: UUID,
    attemptID: UUID
  ) -> String {
    "\(launchID.uuidString).\(attemptID.uuidString).stop"
  }
}
