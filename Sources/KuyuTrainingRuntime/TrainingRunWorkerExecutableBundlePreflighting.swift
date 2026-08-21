import Foundation

public protocol TrainingRunWorkerExecutableBundlePreflighting: Sendable {
  func verifyBundle(
    at rootURL: URL,
    executableRelativePath: String
  ) throws
}
