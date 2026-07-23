import Foundation
import KuyuEvolution
import KuyuTrainingContracts

public struct TrainingRunSummaryOutcomeArtifactValidator: Sendable {
  public enum ValidationError: Error, Sendable, Equatable {
    case unsupportedSchemaVersion(Int)
    case runIDMismatch(expected: String, actual: String)
    case artifactRootMismatch(expected: String, actual: String)
    case nonTerminalState(TrainingRunTerminalState)
    case failedOutcomeMissingReason
    case rejectedOutcomeMissingReason
    case failedOutcomeHasAcceptedCheckpoint
    case rejectedOutcomeHasAcceptedCheckpoint
    case cancelledOutcomeHasAcceptedCheckpoint
    case acceptedCheckpointWrongKind(ModelBundleReferenceKind)
    case acceptedCheckpointOutsideArtifactRoot(path: String, root: String)
    case acceptedCheckpointMissingBundleID
    case acceptedCheckpointMissingDigest
    case acceptedCheckpointInvalidDigest(String)
    case acceptedCheckpointIntegrityFailure(path: String, reason: String)
    case acceptedCheckpointDigestMismatch(expected: String, actual: String)
    case nonFiniteCompletedAt
    case missingWorkerAttemptIdentity
    case workerAttemptIdentityMismatch(
      expected: TrainingRunWorkerAttemptIdentity,
      actual: TrainingRunWorkerAttemptIdentity
    )
    case invalidWorkerLaunchDigest(String)
  }

  public init() {}

  public func validate(
    _ artifact: TrainingRunSummaryOutcomeArtifact,
    expectedRunID: TrainingRunID? = nil,
    expectedWorkerAttemptIdentity: TrainingRunWorkerAttemptIdentity? = nil,
    artifactRoot: URL
  ) throws {
    guard artifact.schemaVersion == TrainingRunSummaryOutcomeArtifact.currentSchemaVersion else {
      throw ValidationError.unsupportedSchemaVersion(artifact.schemaVersion)
    }
    guard artifact.completedAt.timeIntervalSince1970.isFinite else {
      throw ValidationError.nonFiniteCompletedAt
    }
    if let identity = artifact.workerAttemptIdentity {
      guard isSHA256Digest(identity.launchSHA256Digest) else {
        throw ValidationError.invalidWorkerLaunchDigest(identity.launchSHA256Digest)
      }
    }
    if let expectedWorkerAttemptIdentity {
      guard let actual = artifact.workerAttemptIdentity else {
        throw ValidationError.missingWorkerAttemptIdentity
      }
      guard actual == expectedWorkerAttemptIdentity else {
        throw ValidationError.workerAttemptIdentityMismatch(
          expected: expectedWorkerAttemptIdentity,
          actual: actual
        )
      }
    }
    if let expectedRunID, artifact.summary.runID != expectedRunID {
      throw ValidationError.runIDMismatch(
        expected: expectedRunID.rawValue,
        actual: artifact.summary.runID.rawValue
      )
    }
    let expectedRoot = Self.resolvedPath(artifactRoot)
    let actualRoot = Self.resolvedPath(artifact.summary.artifactRoot)
    guard expectedRoot == actualRoot else {
      throw ValidationError.artifactRootMismatch(
        expected: expectedRoot,
        actual: actualRoot
      )
    }
    switch artifact.summary.terminalState {
    case .running:
      throw ValidationError.nonTerminalState(.running)
    case .completed:
      try validateAcceptedCheckpointIfPresent(
        artifact.summary.acceptedCheckpoint,
        artifactRoot: artifactRoot
      )
    case .failed:
      guard !artifact.summary.failureReasons.isEmpty else {
        throw ValidationError.failedOutcomeMissingReason
      }
      guard artifact.summary.acceptedCheckpoint == nil else {
        throw ValidationError.failedOutcomeHasAcceptedCheckpoint
      }
    case .rejected:
      guard !artifact.summary.failureReasons.isEmpty else {
        throw ValidationError.rejectedOutcomeMissingReason
      }
      guard artifact.summary.acceptedCheckpoint == nil else {
        throw ValidationError.rejectedOutcomeHasAcceptedCheckpoint
      }
    case .cancelled:
      guard artifact.summary.acceptedCheckpoint == nil else {
        throw ValidationError.cancelledOutcomeHasAcceptedCheckpoint
      }
    }
  }

  private func validateAcceptedCheckpointIfPresent(
    _ checkpoint: ModelBundleReference?,
    artifactRoot: URL
  ) throws {
    guard let checkpoint else { return }
    guard checkpoint.kind == .accepted else {
      throw ValidationError.acceptedCheckpointWrongKind(checkpoint.kind)
    }
    guard !checkpoint.bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ValidationError.acceptedCheckpointMissingBundleID
    }
    guard let expectedDigest = checkpoint.contentHash else {
      throw ValidationError.acceptedCheckpointMissingDigest
    }
    guard isSHA256Digest(expectedDigest) else {
      throw ValidationError.acceptedCheckpointInvalidDigest(expectedDigest)
    }
    let rootPath = Self.resolvedPath(artifactRoot)
    let checkpointPath = Self.resolvedPath(checkpoint.url)
    guard Self.isDescendantPath(checkpointPath, of: rootPath) else {
      throw ValidationError.acceptedCheckpointOutsideArtifactRoot(
        path: checkpointPath,
        root: rootPath
      )
    }
    let reference: EvolutionCheckpointReference
    do {
      reference = try EvolutionCheckpointIntegrity().reference(
        checkpointID: checkpoint.bundleID,
        checkpointURL: checkpoint.url,
        artifactRoot: artifactRoot
      )
    } catch {
      throw ValidationError.acceptedCheckpointIntegrityFailure(
        path: checkpointPath,
        reason: String(describing: error)
      )
    }
    guard reference.sha256Digest == expectedDigest.lowercased() else {
      throw ValidationError.acceptedCheckpointDigestMismatch(
        expected: expectedDigest.lowercased(),
        actual: reference.sha256Digest
      )
    }
  }

  private static func resolvedPath(_ url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
  }

  private static func isDescendantPath(_ path: String, of root: String) -> Bool {
    path == root || path.hasPrefix(root + "/")
  }

  private func isSHA256Digest(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { byte in
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
      }
  }
}
