import Darwin
import Foundation
import KuyuTrainingContracts
import KuyuTrainingValidation

public struct TrainingRunWorkerProcessLauncher: Sendable {
  public enum LaunchError: Error, Sendable, Equatable {
    case invalidExecutable(path: String)
    case symbolicLinkExecutable(path: String)
    case executableUnavailable(path: String)
  }

  public static let standardOutputFileName = "worker.stdout.log"
  public static let standardErrorFileName = "worker.stderr.log"

  private let configuration: TrainingRunWorkerProcessConfiguration
  private let executableBundlePreflight:
    (any TrainingRunWorkerExecutableBundlePreflighting)?

  public init(
    configuration: TrainingRunWorkerProcessConfiguration,
    executableBundlePreflight:
      (any TrainingRunWorkerExecutableBundlePreflighting)? = nil
  ) {
    self.configuration = configuration
    self.executableBundlePreflight = executableBundlePreflight
  }

  public func launch(
    _ artifact: TrainingRunWorkerLaunchArtifact
  ) async throws -> TrainingRunWorkerProcessHandle {
    try verifyExecutableBundle(configuration.executableSource)
    let executable = try validatedExecutable(
      configuration.executableSource.executableURL
    )
    let roots = TrainingRunWorkerAuthorizedRoots(artifact: artifact)
    try TrainingRunWorkerPathAuthorizationPolicy(
      allowedArtifactRoots: roots.artifactRoots,
      allowedSourceRoots: roots.sourceRoots,
      allowedProjectRoots: roots.projectRoots
    ).validate(artifact)
    try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: roots.sourceRoots
    ).verify(artifact)

    let store = TrainingRunWorkerLaunchArtifactStore(
      rootDirectory: configuration.launchRootDirectory
    )
    let executableStager = TrainingRunWorkerExecutableStager()
    let receipt = try store.write(artifact) { launchDirectory in
      _ = try executableStager.stage(
        source: configuration.executableSource,
        expectedIdentity: executable.identity,
        resourceBundles: configuration.resourceBundles,
        in: launchDirectory
      )
      return try TrainingRunWorkerSourceSnapshotStore().materializedArtifact(
        artifact,
        in: launchDirectory
      )
    }
    let materializedArtifact = receipt.artifact
    let materializedRoots = TrainingRunWorkerAuthorizedRoots(artifact: materializedArtifact)
    try TrainingRunWorkerPathAuthorizationPolicy(
      allowedArtifactRoots: materializedRoots.artifactRoots,
      allowedSourceRoots: materializedRoots.sourceRoots,
      allowedProjectRoots: materializedRoots.projectRoots
    ).validate(materializedArtifact)
    try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: materializedRoots.sourceRoots
    ).verify(materializedArtifact)
    let workerAttemptIdentity = TrainingRunWorkerAttemptIdentity(
      launchID: artifact.launchID,
      attemptID: artifact.attemptID,
      launchSHA256Digest: receipt.sha256Digest
    )
    let launchDirectory = store.launchDirectory(for: artifact.launchID)
    let stagedExecutableSource = try executableStager.stagedSource(
      source: configuration.executableSource,
      in: launchDirectory
    )
    try verifyExecutableBundle(stagedExecutableSource)
    let stagedExecutable = try validatedExecutable(
      stagedExecutableSource.executableURL
    )
    let standardOutputURL = launchDirectory.appendingPathComponent(
      Self.standardOutputFileName,
      isDirectory: false
    )
    let standardErrorURL = launchDirectory.appendingPathComponent(
      Self.standardErrorFileName,
      isDirectory: false
    )
    var arguments = [
      "run-learning-campaign-worker",
      "--launch-root", configuration.launchRootDirectory.path,
      "--launch-id", artifact.launchID.uuidString,
      "--launch-digest", receipt.sha256Digest,
    ]
    arguments.append(contentsOf: materializedRoots.workerArguments)

    let process = TrainingRunWorkerChildProcess()
    let processID = try await process.start(
      executableURL: stagedExecutable.url,
      arguments: arguments,
      standardOutputURL: standardOutputURL,
      standardErrorURL: standardErrorURL,
      expectedExecutableIdentity: stagedExecutable.identity
    )
    return TrainingRunWorkerProcessHandle(
      runID: materializedArtifact.operation.runID,
      artifactRoot: materializedArtifact.operation.artifactRoot,
      progressRoot: launchDirectory,
      workerAttemptIdentity: workerAttemptIdentity,
      processID: processID,
      standardOutputURL: standardOutputURL,
      standardErrorURL: standardErrorURL,
      process: process,
      stopRequest: materializedArtifact.operation.configuration.artifacts.stopSentinelPath == nil
        ? nil
        : TrainingRunWorkerStopRequest(
          artifactRoot: materializedArtifact.operation.artifactRoot,
          launchID: materializedArtifact.launchID,
          attemptID: materializedArtifact.attemptID
        )
    )
  }

  private func validatedExecutable(
    _ requestedURL: URL
  ) throws -> (url: URL, identity: TrainingRunWorkerExecutableIdentity) {
    do {
      return try TrainingRunWorkerExecutableIdentity.validated(requestedURL)
    } catch let error as TrainingRunWorkerExecutableIdentity.IdentityError {
      switch error {
      case .invalidPath:
        throw LaunchError.invalidExecutable(path: requestedURL.absoluteString)
      case .openFailed(_, let code) where code == ELOOP:
        throw LaunchError.symbolicLinkExecutable(path: requestedURL.path)
      case .openFailed, .inspectionFailed, .readFailed, .notExecutable:
        throw LaunchError.executableUnavailable(path: requestedURL.path)
      }
    }
  }

  private func verifyExecutableBundle(
    _ source: TrainingRunWorkerExecutableSource
  ) throws {
    guard let executableBundlePreflight,
      let root = source.bundleRootURL,
      let executableRelativePath = source.executableRelativePath
    else {
      return
    }
    try executableBundlePreflight.verifyBundle(
      at: root,
      executableRelativePath: executableRelativePath
    )
  }
}
