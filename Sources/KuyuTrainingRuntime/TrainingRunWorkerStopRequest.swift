import Darwin
import Foundation
import KuyuTrainingContracts

public struct TrainingRunWorkerStopRequest: Sendable, Equatable {
  public enum StopRequestError: Error, Sendable, Equatable {
    case invalidArtifactRoot(String)
    case unsafeDirectory(String)
    case unexpectedOwner(path: String, expected: UInt32, actual: UInt32)
    case directoryCreationFailed(path: String, code: Int32)
    case directoryOpenFailed(path: String, code: Int32)
    case sentinelOpenFailed(path: String, code: Int32)
    case invalidExistingSentinel(String)
    case syncFailed(path: String, code: Int32)
  }

  public static let controlDirectoryName = TrainingRunWorkerControlPath.directoryName

  public let artifactRoot: URL
  public let launchID: UUID
  public let attemptID: UUID

  public init(artifactRoot: URL, launchID: UUID, attemptID: UUID) {
    self.artifactRoot = artifactRoot
    self.launchID = launchID
    self.attemptID = attemptID
  }

  public var sentinelURL: URL {
    Self.sentinelURL(in: artifactRoot, launchID: launchID, attemptID: attemptID)
  }

  public static func sentinelURL(
    in artifactRoot: URL,
    launchID: UUID,
    attemptID: UUID
  ) -> URL {
    TrainingRunWorkerControlPath.stopSentinelURL(
      in: artifactRoot,
      launchID: launchID,
      attemptID: attemptID
    )
  }

  public func request() throws {
    let root = artifactRoot.standardizedFileURL.resolvingSymlinksInPath()
    guard root.isFileURL, root.path.hasPrefix("/") else {
      throw StopRequestError.invalidArtifactRoot(artifactRoot.absoluteString)
    }
    try requireOwnedArtifactDirectory(root)
    let controlDirectory = root.appendingPathComponent(
      Self.controlDirectoryName,
      isDirectory: true
    )
    try prepareControlDirectory(controlDirectory)

    let directoryDescriptor = controlDirectory.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard directoryDescriptor >= 0 else {
      throw StopRequestError.directoryOpenFailed(
        path: controlDirectory.path,
        code: errno
      )
    }
    defer { Darwin.close(directoryDescriptor) }

    let fileName = TrainingRunWorkerControlPath.stopSentinelFileName(
      launchID: launchID,
      attemptID: attemptID
    )
    let sentinelDescriptor = fileName.withCString { name in
      Darwin.openat(
        directoryDescriptor,
        name,
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
        S_IRUSR | S_IWUSR
      )
    }
    if sentinelDescriptor < 0 {
      guard errno == EEXIST else {
        throw StopRequestError.sentinelOpenFailed(path: sentinelURL.path, code: errno)
      }
      try requireOwnedRegularFile(sentinelURL)
      return
    }
    defer { Darwin.close(sentinelDescriptor) }
    guard fsync(sentinelDescriptor) == 0 else {
      throw StopRequestError.syncFailed(path: sentinelURL.path, code: errno)
    }
    guard fsync(directoryDescriptor) == 0 else {
      throw StopRequestError.syncFailed(path: controlDirectory.path, code: errno)
    }
  }

  public func clear() throws {
    let root = artifactRoot.standardizedFileURL.resolvingSymlinksInPath()
    guard root.isFileURL, root.path.hasPrefix("/") else {
      throw StopRequestError.invalidArtifactRoot(artifactRoot.absoluteString)
    }
    guard FileManager.default.fileExists(atPath: root.path) else { return }
    try requireOwnedArtifactDirectory(root)
    let controlDirectory = root.appendingPathComponent(
      Self.controlDirectoryName,
      isDirectory: true
    )
    guard FileManager.default.fileExists(atPath: controlDirectory.path) else { return }
    try requirePrivateDirectory(controlDirectory)

    let directoryDescriptor = controlDirectory.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard directoryDescriptor >= 0 else {
      throw StopRequestError.directoryOpenFailed(
        path: controlDirectory.path,
        code: errno
      )
    }
    defer { Darwin.close(directoryDescriptor) }

    let fileName = TrainingRunWorkerControlPath.stopSentinelFileName(
      launchID: launchID,
      attemptID: attemptID
    )
    let result = fileName.withCString { name in
      unlinkat(directoryDescriptor, name, 0)
    }
    if result != 0, errno != ENOENT {
      throw StopRequestError.sentinelOpenFailed(path: sentinelURL.path, code: errno)
    }
    guard fsync(directoryDescriptor) == 0 else {
      throw StopRequestError.syncFailed(path: controlDirectory.path, code: errno)
    }
  }

  public func isRequested() throws -> Bool {
    let root = artifactRoot.standardizedFileURL.resolvingSymlinksInPath()
    guard root.isFileURL, root.path.hasPrefix("/") else {
      throw StopRequestError.invalidArtifactRoot(artifactRoot.absoluteString)
    }
    guard FileManager.default.fileExists(atPath: root.path) else { return false }
    try requireOwnedArtifactDirectory(root)
    let controlDirectory = root.appendingPathComponent(
      Self.controlDirectoryName,
      isDirectory: true
    )
    guard FileManager.default.fileExists(atPath: controlDirectory.path) else { return false }
    try requirePrivateDirectory(controlDirectory)
    guard FileManager.default.fileExists(atPath: sentinelURL.path) else { return false }
    try requireOwnedRegularFile(sentinelURL)
    return true
  }

  private func prepareControlDirectory(_ url: URL) throws {
    if Darwin.mkdir(url.path, S_IRWXU) != 0, errno != EEXIST {
      throw StopRequestError.directoryCreationFailed(path: url.path, code: errno)
    }
    try requirePrivateDirectory(url)
  }

  private func requireOwnedArtifactDirectory(_ url: URL) throws {
    let status = try fileStatus(url)
    guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
      throw StopRequestError.unsafeDirectory(url.path)
    }
    try requireOwner(status, at: url)
    guard status.st_mode & mode_t(0o022) == 0 else {
      throw StopRequestError.unsafeDirectory(url.path)
    }
  }

  private func requirePrivateDirectory(_ url: URL) throws {
    let status = try fileStatus(url)
    guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
      throw StopRequestError.unsafeDirectory(url.path)
    }
    try requireOwner(status, at: url)
    guard status.st_mode & mode_t(0o077) == 0 else {
      throw StopRequestError.unsafeDirectory(url.path)
    }
  }

  private func requireOwnedRegularFile(_ url: URL) throws {
    let status = try fileStatus(url)
    guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
      throw StopRequestError.invalidExistingSentinel(url.path)
    }
    try requireOwner(status, at: url)
    guard status.st_mode & mode_t(0o077) == 0 else {
      throw StopRequestError.invalidExistingSentinel(url.path)
    }
  }

  private func requireOwner(_ status: stat, at url: URL) throws {
    guard status.st_uid == geteuid() else {
      throw StopRequestError.unexpectedOwner(
        path: url.path,
        expected: geteuid(),
        actual: status.st_uid
      )
    }
  }

  private func fileStatus(_ url: URL) throws -> stat {
    var status = stat()
    let result = url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return lstat(path, &status)
    }
    guard result == 0 else {
      throw StopRequestError.unsafeDirectory(url.path)
    }
    return status
  }
}
