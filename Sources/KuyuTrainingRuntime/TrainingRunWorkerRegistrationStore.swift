import Darwin
import Foundation

public struct TrainingRunWorkerRegistrationStore: Sendable {
  public enum RegistrationError: Error, Sendable, Equatable {
    case invalidOwnershipRoot(String)
    case openFailed(path: String, code: Int32)
    case unsafeFile(path: String)
    case unexpectedOwner(path: String, expected: UInt32, actual: UInt32)
    case unsafePermissions(path: String, mode: UInt16)
    case metadataTooLarge(path: String, actual: Int64)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)
    case unsupportedSchemaVersion(Int)
    case ownershipKeyMismatch(expected: String, actual: String)
    case artifactRootMismatch(expected: String, actual: String)
    case invalidProcessID(Int32)
    case invalidLaunchDigest(String)
    case attemptIDMismatch(expected: UUID, actual: UUID)
    case metadataIdentityMismatch(
      expected: TrainingRunWorkerLease.Metadata,
      actual: TrainingRunWorkerLease.Metadata
    )
    case fileChangedDuringRead(path: String)
    case removeFailed(path: String, code: Int32)
    case directorySyncFailed(path: String, code: Int32)
    case lockProbeFailed(path: String, code: Int32)
  }

  public static let maximumMetadataByteCount: Int64 = 65_536

  public let ownershipRootDirectory: URL

  public init(ownershipRootDirectory: URL) {
    self.ownershipRootDirectory = ownershipRootDirectory
  }

  public func registration(
    for artifactRoot: URL
  ) throws -> TrainingRunWorkerLease.Metadata? {
    let canonicalRoot = artifactRoot.standardizedFileURL.resolvingSymlinksInPath()
    guard canonicalRoot.isFileURL, canonicalRoot.path.hasPrefix("/") else {
      throw RegistrationError.invalidOwnershipRoot(artifactRoot.absoluteString)
    }
    let ownershipKey = TrainingRunWorkerLease.ownershipKey(for: canonicalRoot)
    guard let directoryDescriptor = try ownershipDirectoryDescriptorIfPresent() else {
      return nil
    }
    defer { Darwin.close(directoryDescriptor) }
    return try registration(
      for: canonicalRoot,
      ownershipKey: ownershipKey,
      directoryDescriptor: directoryDescriptor
    )
  }

  func removeRegistration(
    matching expected: TrainingRunWorkerLease.Metadata
  ) throws {
    let fileName = expected.ownershipKey + ".json"
    let metadataURL = ownershipRootDirectory.appendingPathComponent(
      fileName,
      isDirectory: false
    )
    let directoryDescriptor = ownershipRootDirectory.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard directoryDescriptor >= 0 else {
      throw RegistrationError.openFailed(
        path: ownershipRootDirectory.path,
        code: errno
      )
    }
    defer { Darwin.close(directoryDescriptor) }
    try validateOwnershipDirectoryDescriptor(
      directoryDescriptor,
      path: ownershipRootDirectory.path
    )

    let descriptor = fileName.withCString { name in
      Darwin.openat(directoryDescriptor, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else {
      throw RegistrationError.openFailed(path: metadataURL.path, code: errno)
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    let snapshot = try snapshot(
      descriptor: descriptor,
      handle: handle,
      path: metadataURL.path
    )
    let current = try decodedRegistration(
      from: snapshot.data,
      metadataURL: metadataURL,
      expectedArtifactRoot: expected.artifactRoot,
      expectedOwnershipKey: expected.ownershipKey
    )
    guard current.attemptID == expected.attemptID else {
      throw RegistrationError.attemptIDMismatch(
        expected: expected.attemptID,
        actual: current.attemptID
      )
    }
    guard current == expected else {
      throw RegistrationError.metadataIdentityMismatch(
        expected: expected,
        actual: current
      )
    }

    var statusBeforeRemoval = stat()
    let statusResult = fileName.withCString { name in
      fstatat(directoryDescriptor, name, &statusBeforeRemoval, AT_SYMLINK_NOFOLLOW)
    }
    guard statusResult == 0 else {
      throw RegistrationError.removeFailed(path: metadataURL.path, code: errno)
    }
    try validate(statusBeforeRemoval, path: metadataURL.path)
    guard statusBeforeRemoval.st_dev == snapshot.device,
      statusBeforeRemoval.st_ino == snapshot.inode
    else {
      throw RegistrationError.fileChangedDuringRead(path: metadataURL.path)
    }

    let removeResult = fileName.withCString { name in
      unlinkat(directoryDescriptor, name, 0)
    }
    guard removeResult == 0 else {
      throw RegistrationError.removeFailed(path: metadataURL.path, code: errno)
    }
    guard fsync(directoryDescriptor) == 0 else {
      throw RegistrationError.directorySyncFailed(
        path: ownershipRootDirectory.path,
        code: errno
      )
    }
  }

  private func decodedRegistration(
    from data: Data,
    metadataURL: URL,
    expectedArtifactRoot: URL,
    expectedOwnershipKey: String
  ) throws -> TrainingRunWorkerLease.Metadata {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let metadata: TrainingRunWorkerLease.Metadata
    do {
      metadata = try decoder.decode(TrainingRunWorkerLease.Metadata.self, from: data)
    } catch {
      throw RegistrationError.decodeFailed(
        path: metadataURL.path,
        reason: String(describing: error)
      )
    }
    guard metadata.schemaVersion == TrainingRunWorkerLease.Metadata.currentSchemaVersion else {
      throw RegistrationError.unsupportedSchemaVersion(metadata.schemaVersion)
    }
    guard metadata.ownershipKey == expectedOwnershipKey else {
      throw RegistrationError.ownershipKeyMismatch(
        expected: expectedOwnershipKey,
        actual: metadata.ownershipKey
      )
    }
    let registeredRoot = metadata.artifactRoot.standardizedFileURL.resolvingSymlinksInPath()
    let expectedRoot = expectedArtifactRoot.standardizedFileURL.resolvingSymlinksInPath()
    guard registeredRoot == expectedRoot else {
      throw RegistrationError.artifactRootMismatch(
        expected: expectedRoot.path,
        actual: registeredRoot.path
      )
    }
    guard metadata.processID > 0 else {
      throw RegistrationError.invalidProcessID(metadata.processID)
    }
    guard isSHA256Digest(metadata.launchSHA256Digest) else {
      throw RegistrationError.invalidLaunchDigest(metadata.launchSHA256Digest)
    }
    return metadata
  }

  public func isActive(_ metadata: TrainingRunWorkerLease.Metadata) throws -> Bool {
    guard let directoryDescriptor = try ownershipDirectoryDescriptorIfPresent() else {
      return false
    }
    defer { Darwin.close(directoryDescriptor) }
    let lockFileName = metadata.ownershipKey + ".lock"
    let lockURL = ownershipRootDirectory.appendingPathComponent(
      lockFileName,
      isDirectory: false
    )
    let descriptor = lockFileName.withCString { name in
      Darwin.openat(directoryDescriptor, name, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else {
      if errno == ENOENT { return false }
      throw RegistrationError.openFailed(path: lockURL.path, code: errno)
    }
    defer { Darwin.close(descriptor) }
    try validateDescriptor(descriptor, path: lockURL.path)

    if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
      let unlockResult = flock(descriptor, LOCK_UN)
      guard unlockResult == 0 else {
        throw RegistrationError.lockProbeFailed(path: lockURL.path, code: errno)
      }
      return false
    }
    guard errno == EWOULDBLOCK || errno == EAGAIN else {
      throw RegistrationError.lockProbeFailed(path: lockURL.path, code: errno)
    }
    let current: TrainingRunWorkerLease.Metadata
    do {
      guard let registration = try registration(
        for: metadata.artifactRoot,
        ownershipKey: metadata.ownershipKey,
        directoryDescriptor: directoryDescriptor
      ) else {
        return true
      }
      current = registration
    } catch RegistrationError.fileChangedDuringRead(_) {
      return true
    }
    return current == metadata
  }

  private struct FileSnapshot {
    let data: Data
    let device: dev_t
    let inode: ino_t
  }

  private func registration(
    for canonicalArtifactRoot: URL,
    ownershipKey: String,
    directoryDescriptor: Int32
  ) throws -> TrainingRunWorkerLease.Metadata? {
    let fileName = ownershipKey + ".json"
    let metadataURL = ownershipRootDirectory.appendingPathComponent(
      fileName,
      isDirectory: false
    )
    guard let snapshot = try snapshotIfPresent(
      fileName: fileName,
      url: metadataURL,
      directoryDescriptor: directoryDescriptor
    ) else {
      return nil
    }
    return try decodedRegistration(
      from: snapshot.data,
      metadataURL: metadataURL,
      expectedArtifactRoot: canonicalArtifactRoot,
      expectedOwnershipKey: ownershipKey
    )
  }

  private func ownershipDirectoryDescriptorIfPresent() throws -> Int32? {
    let descriptor = ownershipRootDirectory.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else {
      if errno == ENOENT { return nil }
      throw RegistrationError.openFailed(path: ownershipRootDirectory.path, code: errno)
    }
    do {
      try validateOwnershipDirectoryDescriptor(
        descriptor,
        path: ownershipRootDirectory.path
      )
    } catch {
      Darwin.close(descriptor)
      throw error
    }
    return descriptor
  }

  private func snapshotIfPresent(
    fileName: String,
    url: URL,
    directoryDescriptor: Int32
  ) throws -> FileSnapshot? {
    let descriptor = fileName.withCString { name in
      Darwin.openat(directoryDescriptor, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else {
      if errno == ENOENT { return nil }
      throw RegistrationError.openFailed(path: url.path, code: errno)
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    return try snapshot(descriptor: descriptor, handle: handle, path: url.path)
  }

  private func snapshot(
    descriptor: Int32,
    handle: FileHandle,
    path: String
  ) throws -> FileSnapshot {
    var status = stat()
    guard fstat(descriptor, &status) == 0 else {
      throw RegistrationError.readFailed(path: path, reason: "fstat errno=\(errno)")
    }
    try validate(status, path: path)
    guard status.st_size >= 0, status.st_size <= Self.maximumMetadataByteCount else {
      throw RegistrationError.metadataTooLarge(path: path, actual: status.st_size)
    }
    let data: Data
    do {
      data = try handle.read(upToCount: Int(Self.maximumMetadataByteCount) + 1) ?? Data()
    } catch {
      throw RegistrationError.readFailed(path: path, reason: String(describing: error))
    }
    guard data.count <= Self.maximumMetadataByteCount else {
      throw RegistrationError.metadataTooLarge(path: path, actual: Int64(data.count))
    }
    var statusAfterRead = stat()
    guard fstat(descriptor, &statusAfterRead) == 0 else {
      throw RegistrationError.readFailed(path: path, reason: "fstat errno=\(errno)")
    }
    guard statusAfterRead.st_dev == status.st_dev,
      statusAfterRead.st_ino == status.st_ino,
      statusAfterRead.st_size == status.st_size,
      statusAfterRead.st_mtimespec.tv_sec == status.st_mtimespec.tv_sec,
      statusAfterRead.st_mtimespec.tv_nsec == status.st_mtimespec.tv_nsec,
      statusAfterRead.st_ctimespec.tv_sec == status.st_ctimespec.tv_sec,
      statusAfterRead.st_ctimespec.tv_nsec == status.st_ctimespec.tv_nsec,
      Int64(data.count) == status.st_size
    else {
      throw RegistrationError.fileChangedDuringRead(path: path)
    }
    return FileSnapshot(
      data: data,
      device: status.st_dev,
      inode: status.st_ino
    )
  }

  private func validateOwnershipDirectoryDescriptor(
    _ descriptor: Int32,
    path: String
  ) throws {
    var status = stat()
    guard fstat(descriptor, &status) == 0 else {
      throw RegistrationError.readFailed(path: path, reason: "fstat errno=\(errno)")
    }
    guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
      throw RegistrationError.invalidOwnershipRoot(path)
    }
    guard status.st_uid == geteuid() else {
      throw RegistrationError.unexpectedOwner(
        path: path,
        expected: geteuid(),
        actual: status.st_uid
      )
    }
    let permissions = status.st_mode & mode_t(0o777)
    guard permissions & mode_t(0o077) == 0 else {
      throw RegistrationError.unsafePermissions(path: path, mode: UInt16(permissions))
    }
  }

  private func validateDescriptor(_ descriptor: Int32, path: String) throws {
    var status = stat()
    guard fstat(descriptor, &status) == 0 else {
      throw RegistrationError.readFailed(path: path, reason: "fstat errno=\(errno)")
    }
    try validate(status, path: path)
  }

  private func validate(_ status: stat, path: String) throws {
    guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
      throw RegistrationError.unsafeFile(path: path)
    }
    guard status.st_uid == geteuid() else {
      throw RegistrationError.unexpectedOwner(
        path: path,
        expected: geteuid(),
        actual: status.st_uid
      )
    }
    let permissions = status.st_mode & mode_t(0o777)
    guard permissions & mode_t(0o077) == 0 else {
      throw RegistrationError.unsafePermissions(path: path, mode: UInt16(permissions))
    }
  }

  private func isSHA256Digest(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { byte in
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
      }
  }
}
