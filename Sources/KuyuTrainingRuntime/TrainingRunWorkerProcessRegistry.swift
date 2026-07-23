import Foundation
import KuyuTrainingValidation

public struct TrainingRunWorkerProcessRegistry: Sendable {
  public enum RegistryError: Error, Sendable, Equatable {
    case runIDMismatch(expected: String, actual: String)
    case attemptIDMismatch(expected: UUID, actual: UUID)
    case artifactRootMismatch(expected: String, actual: String)
  }

  private let launchStore: TrainingRunWorkerLaunchArtifactStore
  private let registrationStore: TrainingRunWorkerRegistrationStore

  public init(configuration: TrainingRunWorkerProcessConfiguration) {
    self.launchStore = TrainingRunWorkerLaunchArtifactStore(
      rootDirectory: configuration.launchRootDirectory
    )
    self.registrationStore = TrainingRunWorkerRegistrationStore(
      ownershipRootDirectory: configuration.launchRootDirectory.appendingPathComponent(
        TrainingRunWorkerLease.ownershipDirectoryName,
        isDirectory: true
      )
    )
  }

  public func reconnect(
    artifactRoot: URL
  ) throws -> ReconnectedTrainingRunWorkerProcessHandle? {
    guard let registration = try registrationStore.registration(for: artifactRoot) else {
      return nil
    }
    let launch = try launchStore.validatedArtifact(
      launchID: registration.launchID,
      expectedSHA256Digest: registration.launchSHA256Digest
    )
    guard launch.operation.runID == registration.runID else {
      throw RegistryError.runIDMismatch(
        expected: launch.operation.runID.rawValue,
        actual: registration.runID.rawValue
      )
    }
    guard launch.attemptID == registration.attemptID else {
      throw RegistryError.attemptIDMismatch(
        expected: launch.attemptID,
        actual: registration.attemptID
      )
    }
    let expectedRoot = launch.operation.artifactRoot.standardizedFileURL
      .resolvingSymlinksInPath()
    let registeredRoot = registration.artifactRoot.standardizedFileURL
      .resolvingSymlinksInPath()
    guard expectedRoot == registeredRoot else {
      throw RegistryError.artifactRootMismatch(
        expected: expectedRoot.path,
        actual: registeredRoot.path
      )
    }
    return ReconnectedTrainingRunWorkerProcessHandle(
      registration: registration,
      progressRoot: launchStore.launchDirectory(for: registration.launchID),
      registrationStore: registrationStore
    )
  }
}
