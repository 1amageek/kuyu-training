import Foundation
import Testing

@testable import KuyuTraining

@Suite("Training run worker lease")
struct TrainingRunWorkerLeaseTests {
  @Test(.timeLimit(.minutes(1))) func sameArtifactRootRejectsDifferentLaunch() async throws {
    let paths = try Self.paths("held")
    let digest = String(repeating: "a", count: 64)
    let lease = try Self.lease(paths: paths, digest: digest, runID: "first-run")

    do {
      _ = try Self.lease(paths: paths, digest: digest, runID: "second-run")
      Issue.record("Expected a second writer to be rejected.")
    } catch let error as TrainingRunWorkerLease.LeaseError {
      guard case .alreadyHeld(let path) = error else {
        Issue.record("Unexpected lease error: \(error)")
        try await lease.release()
        return
      }
      #expect(path.hasSuffix(".lock"))
    }

    try await lease.release()
  }

  @Test(.timeLimit(.minutes(1))) func releasedLeaseCanBeAcquiredAgain() async throws {
    let paths = try Self.paths("released")
    let digest = String(repeating: "b", count: 64)
    let first = try Self.lease(paths: paths, digest: digest, runID: "released-run")
    try await first.release()

    let second = try Self.lease(paths: paths, digest: digest, runID: "released-run")
    try await second.release()
  }

  @Test(.timeLimit(.minutes(1))) func leasePublishesDestinationOwnershipMetadata() async throws {
    let paths = try Self.paths("metadata")
    let launchID = UUID()
    let attemptID = UUID()
    let digest = String(repeating: "c", count: 64)
    let lease = try TrainingRunWorkerLease(
      ownershipRootDirectory: paths.ownershipRoot,
      launchID: launchID,
      runID: TrainingRunID("metadata-run"),
      artifactRoot: paths.artifactRoot,
      launchSHA256Digest: digest,
      attemptID: attemptID,
      startedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let data = try Data(contentsOf: lease.metadataFileURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let metadata = try decoder.decode(TrainingRunWorkerLease.Metadata.self, from: data)
    #expect(metadata.launchID == launchID)
    #expect(metadata.attemptID == attemptID)
    #expect(metadata.runID == TrainingRunID("metadata-run"))
    #expect(metadata.artifactRoot.path == paths.artifactRoot.path)
    #expect(metadata.ownershipKey.count == 64)
    #expect(metadata.launchSHA256Digest == digest)
    #expect(metadata.processID > 0)

    try await lease.release()
    #expect(!FileManager.default.fileExists(atPath: lease.metadataFileURL.path))
  }

  @Test(.timeLimit(.minutes(1))) func releaseDoesNotRemoveAnotherAttemptMetadata() async throws {
    let paths = try Self.paths("ownership")
    let lease = try Self.lease(
      paths: paths,
      digest: String(repeating: "d", count: 64),
      runID: "ownership-run"
    )
    let replacement = TrainingRunWorkerLease.Metadata(
      launchID: lease.metadata.launchID,
      attemptID: UUID(),
      runID: lease.metadata.runID,
      artifactRoot: lease.metadata.artifactRoot,
      ownershipKey: lease.metadata.ownershipKey,
      launchSHA256Digest: lease.metadata.launchSHA256Digest,
      processID: lease.metadata.processID,
      startedAt: lease.metadata.startedAt
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(replacement).write(to: lease.metadataFileURL, options: [.atomic])

    await #expect(
      throws: TrainingRunWorkerLease.LeaseError
        .metadataOwnershipChanged(
          expected: lease.metadata.attemptID,
          actual: replacement.attemptID
        )
    ) {
      try await lease.release()
    }
    #expect(FileManager.default.fileExists(atPath: lease.metadataFileURL.path))

    let next = try Self.lease(
      paths: paths,
      digest: replacement.launchSHA256Digest,
      runID: replacement.runID.rawValue
    )
    try FileManager.default.removeItem(at: next.metadataFileURL)
    await #expect(throws: TrainingRunWorkerLease.LeaseError.self) {
      try await next.release()
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func releaseRequiresTheCompleteRegistrationIdentity() async throws {
    let paths = try Self.paths("complete-identity")
    let lease = try Self.lease(
      paths: paths,
      digest: String(repeating: "e", count: 64),
      runID: "complete-identity-run"
    )
    let replacement = TrainingRunWorkerLease.Metadata(
      launchID: UUID(),
      attemptID: lease.metadata.attemptID,
      runID: TrainingRunID("replacement-run"),
      artifactRoot: lease.metadata.artifactRoot,
      ownershipKey: lease.metadata.ownershipKey,
      launchSHA256Digest: String(repeating: "f", count: 64),
      processID: lease.metadata.processID,
      startedAt: lease.metadata.startedAt
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(replacement).write(to: lease.metadataFileURL, options: [.atomic])

    await #expect(
      throws: TrainingRunWorkerLease.LeaseError.metadataIdentityChanged(
        expected: lease.metadata,
        actual: replacement
      )
    ) {
      try await lease.release()
    }
    let metadataDecoder = JSONDecoder()
    metadataDecoder.dateDecodingStrategy = .iso8601
    let persisted = try metadataDecoder.decode(
      TrainingRunWorkerLease.Metadata.self,
      from: Data(contentsOf: lease.metadataFileURL)
    )
    #expect(persisted == replacement)
  }

  @Test(.timeLimit(.minutes(1))) func symbolicLinkOwnershipDirectoryIsRejected() throws {
    let paths = try Self.paths("real")
    try FileManager.default.createDirectory(
      at: paths.ownershipRoot,
      withIntermediateDirectories: false
    )
    let symbolicDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("worker-lease-link-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createSymbolicLink(
      at: symbolicDirectory,
      withDestinationURL: paths.ownershipRoot
    )

    #expect(
      throws: TrainingRunWorkerLease.LeaseError
        .unsafeSymbolicLink(path: symbolicDirectory.path)
    ) {
      _ = try TrainingRunWorkerLease(
        ownershipRootDirectory: symbolicDirectory,
        launchID: UUID(),
        runID: TrainingRunID("symbolic-run"),
        artifactRoot: paths.artifactRoot,
        launchSHA256Digest: String(repeating: "e", count: 64)
      )
    }
  }

  @Test(.timeLimit(.minutes(1))) func broadOwnershipDirectoryIsRejected() throws {
    let paths = try Self.paths("broad-directory")
    try FileManager.default.createDirectory(
      at: paths.ownershipRoot,
      withIntermediateDirectories: false
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: paths.ownershipRoot.path
    )

    #expect(
      throws: TrainingRunWorkerLease.LeaseError.unsafePermissions(
        path: paths.ownershipRoot.path,
        mode: 0o755
      )
    ) {
      _ = try Self.lease(
        paths: paths,
        digest: String(repeating: "1", count: 64),
        runID: "broad-directory-run"
      )
    }
  }

  @Test(.timeLimit(.minutes(1))) func broadExistingLockFileIsRejected() throws {
    let paths = try Self.paths("broad-lock")
    try FileManager.default.createDirectory(
      at: paths.ownershipRoot,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    let ownershipKey = TrainingRunWorkerLease.ownershipKey(
      for: paths.artifactRoot.standardizedFileURL.resolvingSymlinksInPath()
    )
    let lockURL = paths.ownershipRoot.appendingPathComponent(
      ownershipKey + ".lock",
      isDirectory: false
    )
    try Data().write(to: lockURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: lockURL.path
    )

    #expect(
      throws: TrainingRunWorkerLease.LeaseError.unsafePermissions(
        path: lockURL.path,
        mode: 0o644
      )
    ) {
      _ = try Self.lease(
        paths: paths,
        digest: String(repeating: "2", count: 64),
        runID: "broad-lock-run"
      )
    }
  }

  @Test(.timeLimit(.minutes(1))) func releaseRejectsSymbolicLinkMetadata() async throws {
    let paths = try Self.paths("metadata-link")
    let lease = try Self.lease(
      paths: paths,
      digest: String(repeating: "e", count: 64),
      runID: "metadata-link-run"
    )
    let protectedFile = paths.ownershipRoot.appendingPathComponent(
      "protected.json",
      isDirectory: false
    )
    let protectedData = Data("protected".utf8)
    try protectedData.write(to: protectedFile)
    try FileManager.default.removeItem(at: lease.metadataFileURL)
    try FileManager.default.createSymbolicLink(
      at: lease.metadataFileURL,
      withDestinationURL: protectedFile
    )

    await #expect(throws: TrainingRunWorkerLease.LeaseError.self) {
      try await lease.release()
    }
    #expect(try Data(contentsOf: protectedFile) == protectedData)
  }

  @Test(.timeLimit(.minutes(1))) func differentArtifactRootsHaveIndependentLeases() async throws {
    let paths = try Self.paths("independent")
    let otherPaths = (
      ownershipRoot: paths.ownershipRoot,
      artifactRoot: paths.artifactRoot
        .deletingLastPathComponent()
        .appendingPathComponent("other-artifacts", isDirectory: true)
    )
    let first = try Self.lease(
      paths: paths,
      digest: String(repeating: "f", count: 64),
      runID: "first-independent-run"
    )
    let second = try Self.lease(
      paths: otherPaths,
      digest: String(repeating: "0", count: 64),
      runID: "second-independent-run"
    )

    try await first.release()
    try await second.release()
  }

  private static func lease(
    paths: (ownershipRoot: URL, artifactRoot: URL),
    digest: String,
    runID: String
  ) throws -> TrainingRunWorkerLease {
    try TrainingRunWorkerLease(
      ownershipRootDirectory: paths.ownershipRoot,
      launchID: UUID(),
      runID: TrainingRunID(runID),
      artifactRoot: paths.artifactRoot,
      launchSHA256Digest: digest
    )
  }

  private static func paths(_ suffix: String) throws -> (
    ownershipRoot: URL,
    artifactRoot: URL
  ) {
    let spoolRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("worker-lease-\(suffix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: spoolRoot,
      withIntermediateDirectories: true
    )
    return (
      spoolRoot.appendingPathComponent(
        TrainingRunWorkerLease.ownershipDirectoryName,
        isDirectory: true
      ),
      spoolRoot.appendingPathComponent("artifacts", isDirectory: true)
    )
  }
}
