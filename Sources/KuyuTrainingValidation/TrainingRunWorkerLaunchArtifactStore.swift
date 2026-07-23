import CryptoKit
import Darwin
import Foundation
import KuyuTrainingContracts

public struct TrainingRunWorkerLaunchArtifactStore: Sendable {
  public struct Receipt: Sendable, Equatable {
    public let artifact: TrainingRunWorkerLaunchArtifact
    public let fileURL: URL
    public let sha256Digest: String

    public init(
      artifact: TrainingRunWorkerLaunchArtifact,
      fileURL: URL,
      sha256Digest: String
    ) {
      self.artifact = artifact
      self.fileURL = fileURL
      self.sha256Digest = sha256Digest
    }
  }

  public enum StoreError: Error, Sendable, Equatable {
    case invalidRoot(path: String)
    case unsafeSymbolicLink(path: String)
    case launchAlreadyExists(UUID)
    case missingLaunch(UUID)
    case invalidLaunchPath(path: String)
    case invalidExpectedDigest(String)
    case unexpectedOwner(path: String, expected: UInt32, actual: UInt32)
    case unsafePermissions(path: String, mode: UInt16)
    case artifactTooLarge(path: String, actual: Int64, maximum: Int64)
    case digestMismatch(expected: String, actual: String)
    case readFailed(path: String, reason: String)
    case codecFailure(TrainingRunWorkerLaunchArtifactCodec.CodecError)
    case obsoleteSchemaVersion(Int)
    case writeFailed(path: String, reason: String)
    case cleanupFailed(path: String, primary: String, cleanup: String)
    case invalidArtifact(TrainingRunWorkerLaunchArtifactValidator.ValidationError)
    case launchIDMismatch(expected: UUID, actual: UUID)
    case materializedIdentityMismatch(
      expectedLaunchID: UUID,
      actualLaunchID: UUID,
      expectedAttemptID: UUID,
      actualAttemptID: UUID
    )
  }

  public let rootDirectory: URL
  public static let maximumArtifactByteCount: Int64 = 1_048_576
  private let validator: TrainingRunWorkerLaunchArtifactValidator
  private let codec: TrainingRunWorkerLaunchArtifactCodec

  public init(
    rootDirectory: URL,
    validator: TrainingRunWorkerLaunchArtifactValidator =
      TrainingRunWorkerLaunchArtifactValidator(),
    codec: TrainingRunWorkerLaunchArtifactCodec = TrainingRunWorkerLaunchArtifactCodec()
  ) {
    self.rootDirectory = rootDirectory
    self.validator = validator
    self.codec = codec
  }

  public func launchDirectory(for launchID: UUID) -> URL {
    rootDirectory.appendingPathComponent(launchID.uuidString, isDirectory: true)
  }

  public func artifactURL(for launchID: UUID) -> URL {
    launchDirectory(for: launchID).appendingPathComponent(
      TrainingRunWorkerLaunchArtifact.fileName,
      isDirectory: false
    )
  }

  @discardableResult
  public func write(_ artifact: TrainingRunWorkerLaunchArtifact) throws -> Receipt {
    try write(artifact) { _ in artifact }
  }

  @discardableResult
  public func write(
    _ artifact: TrainingRunWorkerLaunchArtifact,
    materializedArtifact: (URL) throws -> TrainingRunWorkerLaunchArtifact
  ) throws -> Receipt {
    try validate(artifact)
    let root = try preparedRootDirectory(createIfMissing: true)
    let launchDirectory = root.appendingPathComponent(
      artifact.launchID.uuidString,
      isDirectory: true
    )
    guard !FileManager.default.fileExists(atPath: launchDirectory.path) else {
      throw StoreError.launchAlreadyExists(artifact.launchID)
    }
    guard isDescendant(launchDirectory, of: root) else {
      throw StoreError.invalidLaunchPath(path: launchDirectory.path)
    }

    do {
      try FileManager.default.createDirectory(
        at: launchDirectory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      let materialized = try materializedArtifact(launchDirectory)
      guard materialized.launchID == artifact.launchID,
        materialized.attemptID == artifact.attemptID
      else {
        throw StoreError.materializedIdentityMismatch(
          expectedLaunchID: artifact.launchID,
          actualLaunchID: materialized.launchID,
          expectedAttemptID: artifact.attemptID,
          actualAttemptID: materialized.attemptID
        )
      }
      try validate(materialized)
      let data = try encodedData(materialized)
      let fileURL = launchDirectory.appendingPathComponent(
        TrainingRunWorkerLaunchArtifact.fileName,
        isDirectory: false
      )
      try data.write(to: fileURL, options: [.atomic])
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: fileURL.path
      )
      return Receipt(
        artifact: materialized,
        fileURL: fileURL,
        sha256Digest: digest(data)
      )
    } catch {
      let primaryError = error
      do {
        if FileManager.default.fileExists(atPath: launchDirectory.path) {
          try prepareForRemoval(launchDirectory)
          try FileManager.default.removeItem(at: launchDirectory)
        }
      } catch {
        throw StoreError.cleanupFailed(
          path: launchDirectory.path,
          primary: String(describing: primaryError),
          cleanup: String(describing: error)
        )
      }
      if let storeError = primaryError as? StoreError {
        throw storeError
      }
      throw StoreError.writeFailed(
        path: launchDirectory.path,
        reason: String(describing: primaryError)
      )
    }
  }

  private func prepareForRemoval(_ root: URL) throws {
    guard Darwin.chmod(root.path, S_IRWXU) == 0 else {
      throw StoreError.writeFailed(
        path: root.path,
        reason: "cleanup chmod errno=\(errno)"
      )
    }
    var enumerationError: Error?
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: nil,
      options: [],
      errorHandler: { _, error in
        enumerationError = error
        return false
      }
    ) else {
      throw StoreError.writeFailed(path: root.path, reason: "cleanup enumeration failed")
    }
    for case let entry as URL in enumerator {
      var status = stat()
      let result = entry.withUnsafeFileSystemRepresentation { path in
        guard let path else { return Int32(-1) }
        return lstat(path, &status)
      }
      guard result == 0 else {
        throw StoreError.writeFailed(
          path: entry.path,
          reason: "cleanup lstat errno=\(errno)"
        )
      }
      let fileType = status.st_mode & mode_t(S_IFMT)
      if fileType == mode_t(S_IFDIR) {
        guard Darwin.chmod(entry.path, S_IRWXU) == 0 else {
          throw StoreError.writeFailed(
            path: entry.path,
            reason: "cleanup chmod errno=\(errno)"
          )
        }
      } else if fileType == mode_t(S_IFREG) {
        guard Darwin.chmod(entry.path, S_IRUSR | S_IWUSR) == 0 else {
          throw StoreError.writeFailed(
            path: entry.path,
            reason: "cleanup chmod errno=\(errno)"
          )
        }
      }
    }
    if let enumerationError {
      throw StoreError.writeFailed(
        path: root.path,
        reason: "cleanup enumeration: \(enumerationError)"
      )
    }
  }

  public func validatedArtifact(
    launchID: UUID,
    expectedSHA256Digest: String
  ) throws -> TrainingRunWorkerLaunchArtifact {
    guard isSHA256Digest(expectedSHA256Digest) else {
      throw StoreError.invalidExpectedDigest(expectedSHA256Digest)
    }
    let root = try preparedRootDirectory(createIfMissing: false)
    let launchDirectory = root.appendingPathComponent(
      launchID.uuidString,
      isDirectory: true
    )
    guard isDescendant(launchDirectory, of: root) else {
      throw StoreError.invalidLaunchPath(path: launchDirectory.path)
    }
    try requireDirectory(launchDirectory)
    let fileURL = launchDirectory.appendingPathComponent(
      TrainingRunWorkerLaunchArtifact.fileName,
      isDirectory: false
    )
    try requireRegularFile(fileURL)

    let data = try validatedData(from: fileURL)
    let actualDigest = digest(data)
    guard actualDigest == expectedSHA256Digest.lowercased() else {
      throw StoreError.digestMismatch(
        expected: expectedSHA256Digest.lowercased(),
        actual: actualDigest
      )
    }
    let decoded: DecodedTrainingRunWorkerLaunchArtifact
    do {
      decoded = try codec.decode(data)
    } catch let error as TrainingRunWorkerLaunchArtifactCodec.CodecError {
      throw StoreError.codecFailure(error)
    }
    let artifact = decoded.artifact
    guard decoded.sourceVersion == TrainingRunWorkerLaunchArtifactWireVersion.current else {
      throw StoreError.obsoleteSchemaVersion(decoded.sourceVersion.rawValue)
    }
    guard artifact.launchID == launchID else {
      throw StoreError.launchIDMismatch(expected: launchID, actual: artifact.launchID)
    }
    try validate(artifact)
    return artifact
  }

  private func validate(_ artifact: TrainingRunWorkerLaunchArtifact) throws {
    do {
      try validator.validate(artifact)
    } catch let error as TrainingRunWorkerLaunchArtifactValidator.ValidationError {
      throw StoreError.invalidArtifact(error)
    }
  }

  private func preparedRootDirectory(createIfMissing: Bool) throws -> URL {
    guard rootDirectory.isFileURL, rootDirectory.path.hasPrefix("/") else {
      throw StoreError.invalidRoot(path: rootDirectory.absoluteString)
    }
    let root = rootDirectory.standardizedFileURL
    if !FileManager.default.fileExists(atPath: root.path) {
      guard createIfMissing else {
        throw StoreError.invalidRoot(path: root.path)
      }
      do {
        try FileManager.default.createDirectory(
          at: root,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700]
        )
      } catch {
        throw StoreError.writeFailed(path: root.path, reason: String(describing: error))
      }
    }
    try requireDirectory(root)
    return root
  }

  private func requireDirectory(_ url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
      if let launchID = UUID(uuidString: url.lastPathComponent) {
        throw StoreError.missingLaunch(launchID)
      }
      throw StoreError.invalidRoot(path: url.path)
    }
    let values: URLResourceValues
    do {
      values = try url.resourceValues(forKeys: [
        .isDirectoryKey,
        .isSymbolicLinkKey,
      ])
    } catch {
      throw StoreError.readFailed(path: url.path, reason: String(describing: error))
    }
    guard values.isSymbolicLink != true else {
      throw StoreError.unsafeSymbolicLink(path: url.path)
    }
    guard values.isDirectory == true else {
      throw StoreError.invalidRoot(path: url.path)
    }
    let status = try fileStatus(at: url)
    guard status.st_uid == geteuid() else {
      throw StoreError.unexpectedOwner(
        path: url.path,
        expected: geteuid(),
        actual: status.st_uid
      )
    }
    let permissions = status.st_mode & mode_t(0o777)
    guard permissions & mode_t(0o077) == 0 else {
      throw StoreError.unsafePermissions(
        path: url.path,
        mode: UInt16(permissions)
      )
    }
  }

  private func requireRegularFile(_ url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw StoreError.readFailed(path: url.path, reason: "missing-file")
    }
    let values: URLResourceValues
    do {
      values = try url.resourceValues(forKeys: [
        .isRegularFileKey,
        .isSymbolicLinkKey,
      ])
    } catch {
      throw StoreError.readFailed(path: url.path, reason: String(describing: error))
    }
    guard values.isSymbolicLink != true else {
      throw StoreError.unsafeSymbolicLink(path: url.path)
    }
    guard values.isRegularFile == true else {
      throw StoreError.invalidLaunchPath(path: url.path)
    }
  }

  private func validatedData(from url: URL) throws -> Data {
    let descriptor = url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else {
      throw StoreError.readFailed(path: url.path, reason: "open errno=\(errno)")
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    var status = stat()
    guard fstat(descriptor, &status) == 0 else {
      throw StoreError.readFailed(path: url.path, reason: "fstat errno=\(errno)")
    }
    guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
      throw StoreError.invalidLaunchPath(path: url.path)
    }
    guard status.st_uid == geteuid() else {
      throw StoreError.unexpectedOwner(
        path: url.path,
        expected: geteuid(),
        actual: status.st_uid
      )
    }
    let permissions = status.st_mode & mode_t(0o777)
    guard permissions & mode_t(0o077) == 0 else {
      throw StoreError.unsafePermissions(
        path: url.path,
        mode: UInt16(permissions)
      )
    }
    guard status.st_size >= 0, status.st_size <= Self.maximumArtifactByteCount else {
      throw StoreError.artifactTooLarge(
        path: url.path,
        actual: status.st_size,
        maximum: Self.maximumArtifactByteCount
      )
    }
    do {
      let data = try handle.read(upToCount: Int(Self.maximumArtifactByteCount) + 1) ?? Data()
      guard data.count <= Self.maximumArtifactByteCount else {
        throw StoreError.artifactTooLarge(
          path: url.path,
          actual: Int64(data.count),
          maximum: Self.maximumArtifactByteCount
        )
      }
      return data
    } catch let error as StoreError {
      throw error
    } catch {
      throw StoreError.readFailed(path: url.path, reason: String(describing: error))
    }
  }

  private func fileStatus(at url: URL) throws -> stat {
    var status = stat()
    let result = url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return lstat(path, &status)
    }
    guard result == 0 else {
      throw StoreError.readFailed(path: url.path, reason: "lstat errno=\(errno)")
    }
    return status
  }

  private func encodedData(_ artifact: TrainingRunWorkerLaunchArtifact) throws -> Data {
    do {
      return try codec.encode(artifact)
    } catch let error as TrainingRunWorkerLaunchArtifactCodec.CodecError {
      throw StoreError.codecFailure(error)
    } catch {
      throw StoreError.writeFailed(
        path: artifactURL(for: artifact.launchID).path,
        reason: String(describing: error)
      )
    }
  }

  private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func isSHA256Digest(_ value: String) -> Bool {
    value.count == 64
      && value.unicodeScalars.allSatisfy { scalar in
        (48...57).contains(scalar.value)
          || (65...70).contains(scalar.value)
          || (97...102).contains(scalar.value)
      }
  }

  private func isDescendant(_ url: URL, of root: URL) -> Bool {
    let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
    return path.hasPrefix(rootPath + "/")
  }
}
