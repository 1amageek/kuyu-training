import Darwin
import Foundation
import KuyuTrainingContracts

public struct TrainingRunSummaryOutcomeArtifactStore: Sendable {
  public enum StoreError: Error, Sendable, Equatable {
    case missingFile(String)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)
    case writeFailed(path: String, reason: String)
    case unsafeFile(String)
    case unexpectedOwner(path: String, expected: UInt32, actual: UInt32)
    case unsafePermissions(path: String, mode: UInt16)
    case artifactTooLarge(path: String, actual: Int64, maximum: Int64)
    case invalidArtifact(TrainingRunSummaryOutcomeArtifactValidator.ValidationError)
    case syncFailed(path: String, code: Int32)
  }

  public static let maximumArtifactByteCount: Int64 = 1_048_576

  private let validator: TrainingRunSummaryOutcomeArtifactValidator

  public init(
    validator: TrainingRunSummaryOutcomeArtifactValidator =
      TrainingRunSummaryOutcomeArtifactValidator()
  ) {
    self.validator = validator
  }

  @discardableResult
  public func write(
    summary: TrainingRunSummary,
    completedAt: Date = Date(),
    expectedRunID: TrainingRunID? = nil,
    workerAttemptIdentity: TrainingRunWorkerAttemptIdentity? = nil,
    to artifactRoot: URL
  ) throws -> URL {
    try write(
      TrainingRunSummaryOutcomeArtifact(
        completedAt: completedAt,
        workerAttemptIdentity: workerAttemptIdentity,
        summary: summary
      ),
      expectedRunID: expectedRunID,
      expectedWorkerAttemptIdentity: workerAttemptIdentity,
      to: artifactRoot
    )
  }

  @discardableResult
  public func write(
    _ artifact: TrainingRunSummaryOutcomeArtifact,
    expectedRunID: TrainingRunID? = nil,
    expectedWorkerAttemptIdentity: TrainingRunWorkerAttemptIdentity? = nil,
    to artifactRoot: URL
  ) throws -> URL {
    do {
      try validator.validate(
        artifact,
        expectedRunID: expectedRunID,
        expectedWorkerAttemptIdentity: expectedWorkerAttemptIdentity,
        artifactRoot: artifactRoot
      )
    } catch let error as TrainingRunSummaryOutcomeArtifactValidator.ValidationError {
      throw StoreError.invalidArtifact(error)
    }
    do {
      try FileManager.default.createDirectory(
        at: artifactRoot,
        withIntermediateDirectories: true
      )
    } catch {
      throw StoreError.writeFailed(
        path: artifactRoot.path,
        reason: String(describing: error)
      )
    }
    let url = artifactURL(
      in: artifactRoot,
      workerAttemptIdentity: artifact.workerAttemptIdentity
    )
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      if artifact.workerAttemptIdentity != nil {
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o700],
          ofItemAtPath: url.deletingLastPathComponent().path
        )
        try syncDirectory(url.deletingLastPathComponent().deletingLastPathComponent())
      }
    } catch {
      throw StoreError.writeFailed(
        path: url.deletingLastPathComponent().path,
        reason: String(describing: error)
      )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    do {
      let data = try encoder.encode(artifact)
      guard data.count <= Self.maximumArtifactByteCount else {
        throw StoreError.artifactTooLarge(
          path: url.path,
          actual: Int64(data.count),
          maximum: Self.maximumArtifactByteCount
        )
      }
      try writeDurably(data, to: url)
    } catch let error as StoreError {
      throw error
    } catch {
      throw StoreError.writeFailed(
        path: url.path,
        reason: String(describing: error)
      )
    }
    return url
  }

  public func validatedArtifact(
    in artifactRoot: URL,
    expectedRunID: TrainingRunID? = nil,
    expectedWorkerAttemptIdentity: TrainingRunWorkerAttemptIdentity? = nil
  ) throws -> TrainingRunSummaryOutcomeArtifact {
    let url = artifactURL(
      in: artifactRoot,
      workerAttemptIdentity: expectedWorkerAttemptIdentity
    )
    let data = try validatedData(from: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let artifact: TrainingRunSummaryOutcomeArtifact
    do {
      artifact = try decoder.decode(TrainingRunSummaryOutcomeArtifact.self, from: data)
    } catch {
      throw StoreError.decodeFailed(
        path: url.path,
        reason: String(describing: error)
      )
    }
    do {
      try validator.validate(
        artifact,
        expectedRunID: expectedRunID,
        expectedWorkerAttemptIdentity: expectedWorkerAttemptIdentity,
        artifactRoot: artifactRoot
      )
    } catch let error as TrainingRunSummaryOutcomeArtifactValidator.ValidationError {
      throw StoreError.invalidArtifact(error)
    }
    return artifact
  }

  public func artifactURL(
    in artifactRoot: URL,
    workerAttemptIdentity: TrainingRunWorkerAttemptIdentity?
  ) -> URL {
    guard let workerAttemptIdentity else {
      return artifactRoot.appendingPathComponent(
        TrainingRunSummaryOutcomeArtifact.fileName,
        isDirectory: false
      )
    }
    return artifactRoot
      .appendingPathComponent(
        TrainingRunSummaryOutcomeArtifact.workerDirectoryName,
        isDirectory: true
      )
      .appendingPathComponent(
        "\(workerAttemptIdentity.launchID.uuidString).\(workerAttemptIdentity.attemptID.uuidString).json",
        isDirectory: false
      )
  }

  private func validatedData(from url: URL) throws -> Data {
    let descriptor = url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else {
      if errno == ENOENT {
        throw StoreError.missingFile(TrainingRunSummaryOutcomeArtifact.fileName)
      }
      throw StoreError.readFailed(path: url.path, reason: "open errno=\(errno)")
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    var status = stat()
    guard fstat(descriptor, &status) == 0 else {
      throw StoreError.readFailed(path: url.path, reason: "fstat errno=\(errno)")
    }
    guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
      throw StoreError.unsafeFile(url.path)
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
      throw StoreError.unsafePermissions(path: url.path, mode: UInt16(permissions))
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

  private func writeDurably(_ data: Data, to url: URL) throws {
    let directory = url.deletingLastPathComponent()
    let directoryDescriptor = directory.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard directoryDescriptor >= 0 else {
      throw StoreError.writeFailed(path: directory.path, reason: "open errno=\(errno)")
    }
    defer { Darwin.close(directoryDescriptor) }
    try validateDirectoryDescriptor(directoryDescriptor, path: directory.path)

    let temporaryName = ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
    let temporaryDescriptor = temporaryName.withCString { name in
      Darwin.openat(
        directoryDescriptor,
        name,
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
        S_IRUSR | S_IWUSR
      )
    }
    guard temporaryDescriptor >= 0 else {
      throw StoreError.writeFailed(path: url.path, reason: "openat errno=\(errno)")
    }
    var temporaryExists = true
    defer {
      Darwin.close(temporaryDescriptor)
      if temporaryExists {
        temporaryName.withCString { name in
          _ = Darwin.unlinkat(directoryDescriptor, name, 0)
        }
      }
    }
    try write(data, descriptor: temporaryDescriptor, path: url.path)
    guard fsync(temporaryDescriptor) == 0 else {
      throw StoreError.syncFailed(path: url.path, code: errno)
    }

    let renameResult = temporaryName.withCString { temporary in
      url.lastPathComponent.withCString { final in
        Darwin.renameat(directoryDescriptor, temporary, directoryDescriptor, final)
      }
    }
    guard renameResult == 0 else {
      throw StoreError.writeFailed(path: url.path, reason: "renameat errno=\(errno)")
    }
    temporaryExists = false
    guard fsync(directoryDescriptor) == 0 else {
      throw StoreError.syncFailed(path: directory.path, code: errno)
    }
  }

  private func write(_ data: Data, descriptor: Int32, path: String) throws {
    try data.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return }
      var written = 0
      while written < data.count {
        let result = Darwin.write(
          descriptor,
          baseAddress.advanced(by: written),
          data.count - written
        )
        if result < 0 {
          if errno == EINTR { continue }
          throw StoreError.writeFailed(path: path, reason: "write errno=\(errno)")
        }
        guard result > 0 else {
          throw StoreError.writeFailed(path: path, reason: "zero-byte write")
        }
        written += result
      }
    }
  }

  private func validateDirectoryDescriptor(_ descriptor: Int32, path: String) throws {
    var status = stat()
    guard fstat(descriptor, &status) == 0 else {
      throw StoreError.writeFailed(path: path, reason: "fstat errno=\(errno)")
    }
    guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
      status.st_uid == geteuid()
    else {
      throw StoreError.unsafeFile(path)
    }
  }

  private func syncDirectory(_ url: URL) throws {
    let descriptor = url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else {
      throw StoreError.writeFailed(path: url.path, reason: "open errno=\(errno)")
    }
    defer { Darwin.close(descriptor) }
    guard fsync(descriptor) == 0 else {
      throw StoreError.syncFailed(path: url.path, code: errno)
    }
  }
}
