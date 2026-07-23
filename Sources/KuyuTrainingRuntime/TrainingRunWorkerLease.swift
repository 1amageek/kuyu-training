import CryptoKit
import Darwin
import Foundation
import KuyuTrainingContracts

public actor TrainingRunWorkerLease {
  public struct Metadata: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let launchID: UUID
    public let attemptID: UUID
    public let runID: TrainingRunID
    public let artifactRoot: URL
    public let ownershipKey: String
    public let launchSHA256Digest: String
    public let processID: Int32
    public let startedAt: Date

    public init(
      schemaVersion: Int = Self.currentSchemaVersion,
      launchID: UUID,
      attemptID: UUID,
      runID: TrainingRunID,
      artifactRoot: URL,
      ownershipKey: String,
      launchSHA256Digest: String,
      processID: Int32,
      startedAt: Date
    ) {
      self.schemaVersion = schemaVersion
      self.launchID = launchID
      self.attemptID = attemptID
      self.runID = runID
      self.artifactRoot = artifactRoot
      self.ownershipKey = ownershipKey
      self.launchSHA256Digest = launchSHA256Digest.lowercased()
      self.processID = processID
      self.startedAt = Date(
        timeIntervalSince1970: startedAt.timeIntervalSince1970.rounded(.down)
      )
    }

    public var attemptIdentity: TrainingRunWorkerAttemptIdentity {
      TrainingRunWorkerAttemptIdentity(
        launchID: launchID,
        attemptID: attemptID,
        launchSHA256Digest: launchSHA256Digest
      )
    }
  }

  public enum LeaseError: Error, Sendable, Equatable {
    case invalidOwnershipDirectory(path: String)
    case invalidArtifactRoot(path: String)
    case unsafeSymbolicLink(path: String)
    case unsafeLockFile(path: String)
    case unexpectedOwner(path: String, expected: UInt32, actual: UInt32)
    case unsafePermissions(path: String, mode: UInt16)
    case openFailed(path: String, code: Int32)
    case inspectionFailed(path: String, code: Int32)
    case alreadyHeld(path: String)
    case lockFailed(path: String, code: Int32)
    case metadataWriteFailed(path: String, reason: String)
    case metadataReadFailed(path: String, reason: String)
    case metadataOwnershipChanged(expected: UUID, actual: UUID)
    case metadataIdentityChanged(expected: Metadata, actual: Metadata)
    case unlockFailed(path: String, code: Int32)
  }

  public static let ownershipDirectoryName = "training-run-worker-ownership"

  public nonisolated let metadata: Metadata
  public nonisolated let lockFileURL: URL
  public nonisolated let metadataFileURL: URL

  private var descriptor: Int32?

  public init(
    ownershipRootDirectory: URL,
    launchID: UUID,
    runID: TrainingRunID,
    artifactRoot: URL,
    launchSHA256Digest: String,
    attemptID: UUID = UUID(),
    startedAt: Date = Date()
  ) throws {
    let ownershipRoot = try Self.preparedOwnershipDirectory(ownershipRootDirectory)
    let canonicalArtifactRoot = artifactRoot.standardizedFileURL.resolvingSymlinksInPath()
    guard canonicalArtifactRoot.isFileURL, canonicalArtifactRoot.path.hasPrefix("/") else {
      throw LeaseError.invalidArtifactRoot(path: canonicalArtifactRoot.absoluteString)
    }
    let ownershipKey = Self.ownershipKey(for: canonicalArtifactRoot)
    let lockFileURL = ownershipRoot.appendingPathComponent(
      ownershipKey + ".lock",
      isDirectory: false
    )
    let metadataFileURL = ownershipRoot.appendingPathComponent(
      ownershipKey + ".json",
      isDirectory: false
    )
    let descriptor = lockFileURL.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return Darwin.open(
        path,
        O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
        S_IRUSR | S_IWUSR
      )
    }
    guard descriptor >= 0 else {
      throw LeaseError.openFailed(path: lockFileURL.path, code: errno)
    }
    do {
      try Self.requirePrivateRegularFile(descriptor, at: lockFileURL)
    } catch {
      Darwin.close(descriptor)
      throw error
    }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      let code = errno
      Darwin.close(descriptor)
      if code == EWOULDBLOCK || code == EAGAIN {
        throw LeaseError.alreadyHeld(path: lockFileURL.path)
      }
      throw LeaseError.lockFailed(path: lockFileURL.path, code: code)
    }

    let metadata = Metadata(
      launchID: launchID,
      attemptID: attemptID,
      runID: runID,
      artifactRoot: canonicalArtifactRoot,
      ownershipKey: ownershipKey,
      launchSHA256Digest: launchSHA256Digest,
      processID: getpid(),
      startedAt: startedAt
    )
    do {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(metadata)
      try data.write(to: metadataFileURL, options: [.atomic])
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: metadataFileURL.path
      )
    } catch {
      flock(descriptor, LOCK_UN)
      Darwin.close(descriptor)
      throw LeaseError.metadataWriteFailed(
        path: metadataFileURL.path,
        reason: String(describing: error)
      )
    }

    self.metadata = metadata
    self.lockFileURL = lockFileURL
    self.metadataFileURL = metadataFileURL
    self.descriptor = descriptor
  }

  deinit {
    if let descriptor {
      flock(descriptor, LOCK_UN)
      Darwin.close(descriptor)
    }
  }

  public func release() throws {
    guard let descriptor else { return }
    var releaseError: LeaseError?
    do {
      let store = TrainingRunWorkerRegistrationStore(
        ownershipRootDirectory: metadataFileURL.deletingLastPathComponent()
      )
      try store.removeRegistration(matching: metadata)
    } catch let error as TrainingRunWorkerRegistrationStore.RegistrationError {
      if case .attemptIDMismatch(let expected, let actual) = error {
        releaseError = .metadataOwnershipChanged(expected: expected, actual: actual)
      } else if case .metadataIdentityMismatch(let expected, let actual) = error {
        releaseError = .metadataIdentityChanged(expected: expected, actual: actual)
      } else {
        releaseError = .metadataReadFailed(
          path: metadataFileURL.path,
          reason: String(describing: error)
        )
      }
    } catch let error as LeaseError {
      releaseError = error
    } catch {
      releaseError = .metadataReadFailed(
        path: metadataFileURL.path,
        reason: String(describing: error)
      )
    }

    if flock(descriptor, LOCK_UN) != 0, releaseError == nil {
      releaseError = .unlockFailed(path: lockFileURL.path, code: errno)
    }
    Darwin.close(descriptor)
    self.descriptor = nil
    if let releaseError {
      throw releaseError
    }
  }

  private static func preparedOwnershipDirectory(_ url: URL) throws -> URL {
    let directory = url.standardizedFileURL
    guard directory.isFileURL, directory.path.hasPrefix("/") else {
      throw LeaseError.invalidOwnershipDirectory(path: directory.absoluteString)
    }
    if !FileManager.default.fileExists(atPath: directory.path) {
      try requireDirectory(
        directory.deletingLastPathComponent(),
        privateAccessRequired: false
      )
      do {
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: false,
          attributes: [.posixPermissions: 0o700]
        )
      } catch {
        guard FileManager.default.fileExists(atPath: directory.path) else {
          throw LeaseError.invalidOwnershipDirectory(path: directory.path)
        }
      }
    }
    try requireDirectory(directory, privateAccessRequired: true)
    return directory
  }

  private static func requireDirectory(
    _ url: URL,
    privateAccessRequired: Bool
  ) throws {
    var status = stat()
    let result = url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return lstat(path, &status)
    }
    guard result == 0 else {
      throw LeaseError.invalidOwnershipDirectory(path: url.path)
    }
    guard status.st_mode & mode_t(S_IFMT) != mode_t(S_IFLNK) else {
      throw LeaseError.unsafeSymbolicLink(path: url.path)
    }
    guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
      throw LeaseError.invalidOwnershipDirectory(path: url.path)
    }
    try requireOwner(status, at: url)
    let permissions = status.st_mode & mode_t(0o777)
    let forbidden = privateAccessRequired ? mode_t(0o077) : mode_t(0o022)
    guard permissions & forbidden == 0 else {
      throw LeaseError.unsafePermissions(path: url.path, mode: UInt16(permissions))
    }
  }

  private static func requirePrivateRegularFile(
    _ descriptor: Int32,
    at url: URL
  ) throws {
    var status = stat()
    guard fstat(descriptor, &status) == 0 else {
      throw LeaseError.inspectionFailed(path: url.path, code: errno)
    }
    guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
      throw LeaseError.unsafeLockFile(path: url.path)
    }
    try requireOwner(status, at: url)
    let permissions = status.st_mode & mode_t(0o777)
    guard permissions & mode_t(0o077) == 0 else {
      throw LeaseError.unsafePermissions(path: url.path, mode: UInt16(permissions))
    }
  }

  private static func requireOwner(_ status: stat, at url: URL) throws {
    guard status.st_uid == geteuid() else {
      throw LeaseError.unexpectedOwner(
        path: url.path,
        expected: geteuid(),
        actual: status.st_uid
      )
    }
  }

  public static func ownershipKey(for artifactRoot: URL) -> String {
    SHA256.hash(data: Data(artifactRoot.path.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }
}
