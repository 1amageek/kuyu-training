import Darwin
import Foundation
import KuyuTrainingContracts

public struct TrainingRunWorkerProgressStore: Sendable {
  public struct JournalCursor: Sendable, Equatable {
    public static let zero = JournalCursor(segmentIndex: 0, byteOffset: 0)

    public let segmentIndex: UInt64
    public let byteOffset: UInt64

    public init(segmentIndex: UInt64, byteOffset: UInt64) {
      self.segmentIndex = segmentIndex
      self.byteOffset = byteOffset
    }
  }

  public struct JournalBatch: Sendable, Equatable {
    public let artifacts: [TrainingRunWorkerProgressArtifact]
    public let nextCursor: JournalCursor
    public let hasMoreBytes: Bool

    public init(
      artifacts: [TrainingRunWorkerProgressArtifact],
      nextCursor: JournalCursor,
      hasMoreBytes: Bool
    ) {
      self.artifacts = artifacts
      self.nextCursor = nextCursor
      self.hasMoreBytes = hasMoreBytes
    }
  }

  public enum StoreError: Error, Equatable, Sendable {
    case openFailed(path: String, code: Int32)
    case unsafeDirectory(String)
    case unsafeFile(String)
    case unexpectedOwner(path: String, expected: UInt32, actual: UInt32)
    case unsafePermissions(path: String, mode: UInt16)
    case artifactTooLarge(path: String, actual: Int64, maximum: Int64)
    case invalidOffset(path: String, requested: UInt64, byteCount: Int64)
    case missingJournalSegment(index: UInt64)
    case invalidJournalSegment(String)
    case writerAlreadyActive(path: String)
    case sequenceDiscontinuity(expected: UInt64, actual: UInt64)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)
    case invalidArtifact(TrainingRunWorkerProgressArtifact.ValidationError)
    case writeFailed(path: String, reason: String)
    case syncFailed(path: String, code: Int32)
  }

  public static let maximumArtifactByteCount: Int64 = 262_144
  public static let defaultSegmentByteCount: Int64 = 16_777_216
  public static let maximumReadBatchByteCount = 4_194_304

  private let segmentByteCount: Int64

  public init(segmentByteCount: Int64 = Self.defaultSegmentByteCount) {
    self.segmentByteCount = max(1, segmentByteCount)
  }

  public actor Writer {
    public nonisolated let initialSequence: UInt64

    private let store: TrainingRunWorkerProgressStore
    private let artifactRoot: URL
    private let workerAttemptIdentity: TrainingRunWorkerAttemptIdentity
    private let directory: URL
    private let directoryDescriptor: Int32
    private let lockDescriptor: Int32
    private var journalDescriptor: Int32
    private var segmentIndex: UInt64
    private var journalByteCount: Int64
    private var sequence: UInt64

    fileprivate init(
      store: TrainingRunWorkerProgressStore,
      artifactRoot: URL,
      workerAttemptIdentity: TrainingRunWorkerAttemptIdentity
    ) throws {
      let setup = try store.writerSetup(
        in: artifactRoot,
        workerAttemptIdentity: workerAttemptIdentity
      )
      self.store = store
      self.artifactRoot = artifactRoot
      self.workerAttemptIdentity = workerAttemptIdentity
      self.directory = setup.directory
      self.directoryDescriptor = setup.directoryDescriptor
      self.lockDescriptor = setup.lockDescriptor
      self.journalDescriptor = setup.journalDescriptor
      self.segmentIndex = setup.segmentIndex
      self.journalByteCount = setup.journalByteCount
      self.sequence = setup.sequence
      self.initialSequence = setup.sequence
    }

    deinit {
      Darwin.close(journalDescriptor)
      _ = flock(lockDescriptor, LOCK_UN)
      Darwin.close(lockDescriptor)
      Darwin.close(directoryDescriptor)
    }

    @discardableResult
    public func append(_ artifact: TrainingRunWorkerProgressArtifact) throws -> URL {
      try store.validated(
        artifact,
        expectedWorkerAttemptIdentity: workerAttemptIdentity
      )
      let expectedSequence = sequence + 1
      guard artifact.sequence == expectedSequence else {
        throw StoreError.sequenceDiscontinuity(
          expected: expectedSequence,
          actual: artifact.sequence
        )
      }
      var record = try store.encodedData(
        artifact,
        path: store.artifactURL(
          in: artifactRoot,
          workerAttemptIdentity: workerAttemptIdentity,
          segmentIndex: segmentIndex
        ).path
      )
      record.append(0x0A)
      guard record.count <= TrainingRunWorkerProgressStore.maximumArtifactByteCount else {
        throw StoreError.artifactTooLarge(
          path: directory.path,
          actual: Int64(record.count),
          maximum: TrainingRunWorkerProgressStore.maximumArtifactByteCount
        )
      }
      if journalByteCount > 0,
        journalByteCount > store.segmentByteCount - Int64(record.count)
      {
        try rotate()
      }
      let url = store.artifactURL(
        in: artifactRoot,
        workerAttemptIdentity: workerAttemptIdentity,
        segmentIndex: segmentIndex
      )
      try store.write(record, descriptor: journalDescriptor, path: url.path)
      guard fsync(journalDescriptor) == 0 else {
        throw StoreError.syncFailed(path: url.path, code: errno)
      }
      guard fsync(directoryDescriptor) == 0 else {
        throw StoreError.syncFailed(path: directory.path, code: errno)
      }
      journalByteCount += Int64(record.count)
      sequence = artifact.sequence
      return url
    }

    private func rotate() throws {
      guard fsync(journalDescriptor) == 0 else {
        throw StoreError.syncFailed(path: directory.path, code: errno)
      }
      let nextSegment = segmentIndex + 1
      let nextName = store.artifactFileName(
        for: workerAttemptIdentity,
        segmentIndex: nextSegment
      )
      let nextDescriptor = nextName.withCString { name in
        Darwin.openat(
          directoryDescriptor,
          name,
          O_WRONLY | O_CREAT | O_EXCL | O_APPEND | O_CLOEXEC | O_NOFOLLOW,
          S_IRUSR | S_IWUSR
        )
      }
      guard nextDescriptor >= 0 else {
        throw StoreError.openFailed(
          path: directory.appendingPathComponent(nextName).path,
          code: errno
        )
      }
      Darwin.close(journalDescriptor)
      journalDescriptor = nextDescriptor
      segmentIndex = nextSegment
      journalByteCount = 0
      guard fsync(directoryDescriptor) == 0 else {
        throw StoreError.syncFailed(path: directory.path, code: errno)
      }
    }
  }

  public func writer(
    in artifactRoot: URL,
    workerAttemptIdentity: TrainingRunWorkerAttemptIdentity
  ) throws -> Writer {
    try Writer(
      store: self,
      artifactRoot: artifactRoot,
      workerAttemptIdentity: workerAttemptIdentity
    )
  }

  @discardableResult
  public func write(
    _ artifact: TrainingRunWorkerProgressArtifact,
    to artifactRoot: URL
  ) async throws -> URL {
    let writer = try writer(
      in: artifactRoot,
      workerAttemptIdentity: artifact.workerAttemptIdentity
    )
    return try await writer.append(artifact)
  }

  public func artifact(
    in artifactRoot: URL,
    expectedWorkerAttemptIdentity: TrainingRunWorkerAttemptIdentity
  ) throws -> TrainingRunWorkerProgressArtifact? {
    var cursor = JournalCursor.zero
    var latest: TrainingRunWorkerProgressArtifact?
    while true {
      let batch = try journalBatch(
        in: artifactRoot,
        expectedWorkerAttemptIdentity: expectedWorkerAttemptIdentity,
        from: cursor
      )
      latest = batch.artifacts.last ?? latest
      guard batch.nextCursor != cursor else { return latest }
      cursor = batch.nextCursor
      guard batch.hasMoreBytes else { return latest }
    }
  }

  public func journalBatch(
    in artifactRoot: URL,
    expectedWorkerAttemptIdentity: TrainingRunWorkerAttemptIdentity,
    from cursor: JournalCursor
  ) throws -> JournalBatch {
    let directory = directoryURL(in: artifactRoot)
    let directoryDescriptor = directory.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard directoryDescriptor >= 0 else {
      if errno == ENOENT {
        return JournalBatch(artifacts: [], nextCursor: cursor, hasMoreBytes: false)
      }
      throw StoreError.openFailed(path: directory.path, code: errno)
    }
    defer { Darwin.close(directoryDescriptor) }
    try validateDirectoryDescriptor(directoryDescriptor, path: directory.path)

    let segments = try segmentIndices(
      directory: directory,
      workerAttemptIdentity: expectedWorkerAttemptIdentity
    )
    guard !segments.isEmpty else {
      return JournalBatch(artifacts: [], nextCursor: cursor, hasMoreBytes: false)
    }
    guard segments.contains(cursor.segmentIndex) else {
      throw StoreError.missingJournalSegment(index: cursor.segmentIndex)
    }
    let fileName = artifactFileName(
      for: expectedWorkerAttemptIdentity,
      segmentIndex: cursor.segmentIndex
    )
    let url = directory.appendingPathComponent(fileName, isDirectory: false)
    let descriptor = fileName.withCString { name in
      Darwin.openat(directoryDescriptor, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else {
      throw StoreError.openFailed(path: url.path, code: errno)
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    var status = stat()
    guard fstat(descriptor, &status) == 0 else {
      throw StoreError.readFailed(path: url.path, reason: "fstat errno=\(errno)")
    }
    try validateFileStatus(status, path: url.path)
    guard status.st_size >= 0 else {
      throw StoreError.readFailed(path: url.path, reason: "negative file size")
    }
    guard cursor.byteOffset <= UInt64(status.st_size) else {
      throw StoreError.invalidOffset(
        path: url.path,
        requested: cursor.byteOffset,
        byteCount: status.st_size
      )
    }
    let nextSegment = segments.first { $0 > cursor.segmentIndex }
    let available = min(
      UInt64(Self.maximumReadBatchByteCount),
      UInt64(status.st_size) - cursor.byteOffset
    )
    guard available > 0 else {
      if let nextSegment {
        return JournalBatch(
          artifacts: [],
          nextCursor: JournalCursor(segmentIndex: nextSegment, byteOffset: 0),
          hasMoreBytes: true
        )
      }
      return JournalBatch(artifacts: [], nextCursor: cursor, hasMoreBytes: false)
    }
    let data: Data
    do {
      try handle.seek(toOffset: cursor.byteOffset)
      data = try handle.read(upToCount: Int(available)) ?? Data()
    } catch {
      throw StoreError.readFailed(path: url.path, reason: String(describing: error))
    }
    guard let finalNewline = data.lastIndex(of: 0x0A) else {
      if data.count > Self.maximumArtifactByteCount {
        throw StoreError.artifactTooLarge(
          path: url.path,
          actual: Int64(data.count),
          maximum: Self.maximumArtifactByteCount
        )
      }
      return JournalBatch(
        artifacts: [],
        nextCursor: cursor,
        hasMoreBytes: true
      )
    }
    let completeEnd = data.index(after: finalNewline)
    let completeData = data[..<completeEnd]
    let records = completeData.split(separator: 0x0A, omittingEmptySubsequences: true)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var artifacts: [TrainingRunWorkerProgressArtifact] = []
    artifacts.reserveCapacity(records.count)
    for record in records {
      guard record.count <= Self.maximumArtifactByteCount else {
        throw StoreError.artifactTooLarge(
          path: url.path,
          actual: Int64(record.count),
          maximum: Self.maximumArtifactByteCount
        )
      }
      let artifact: TrainingRunWorkerProgressArtifact
      do {
        artifact = try decoder.decode(
          TrainingRunWorkerProgressArtifact.self,
          from: Data(record)
        )
      } catch {
        throw StoreError.decodeFailed(path: url.path, reason: String(describing: error))
      }
      try validated(
        artifact,
        expectedWorkerAttemptIdentity: expectedWorkerAttemptIdentity
      )
      artifacts.append(artifact)
    }
    let byteOffset = cursor.byteOffset + UInt64(completeData.count)
    let atSegmentEnd = byteOffset == UInt64(status.st_size)
    if atSegmentEnd, let nextSegment {
      return JournalBatch(
        artifacts: artifacts,
        nextCursor: JournalCursor(segmentIndex: nextSegment, byteOffset: 0),
        hasMoreBytes: true
      )
    }
    return JournalBatch(
      artifacts: artifacts,
      nextCursor: JournalCursor(
        segmentIndex: cursor.segmentIndex,
        byteOffset: byteOffset
      ),
      hasMoreBytes: UInt64(status.st_size) > byteOffset
    )
  }

  public func artifactURL(
    in artifactRoot: URL,
    workerAttemptIdentity: TrainingRunWorkerAttemptIdentity
  ) -> URL {
    artifactURL(
      in: artifactRoot,
      workerAttemptIdentity: workerAttemptIdentity,
      segmentIndex: 0
    )
  }

  public func artifactURL(
    in artifactRoot: URL,
    workerAttemptIdentity: TrainingRunWorkerAttemptIdentity,
    segmentIndex: UInt64
  ) -> URL {
    directoryURL(in: artifactRoot).appendingPathComponent(
      artifactFileName(
        for: workerAttemptIdentity,
        segmentIndex: segmentIndex
      ),
      isDirectory: false
    )
  }

  private struct WriterSetup {
    let directory: URL
    let directoryDescriptor: Int32
    let lockDescriptor: Int32
    let journalDescriptor: Int32
    let segmentIndex: UInt64
    let journalByteCount: Int64
    let sequence: UInt64
  }

  private func writerSetup(
    in artifactRoot: URL,
    workerAttemptIdentity: TrainingRunWorkerAttemptIdentity
  ) throws -> WriterSetup {
    let directory = directoryURL(in: artifactRoot)
    try prepareDirectory(directory)
    let directoryDescriptor = directory.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard directoryDescriptor >= 0 else {
      throw StoreError.openFailed(path: directory.path, code: errno)
    }
    var lockDescriptor = Int32(-1)
    var journalDescriptor = Int32(-1)
    do {
      try validateDirectoryDescriptor(directoryDescriptor, path: directory.path)
      let lockName = writerLockFileName(for: workerAttemptIdentity)
      lockDescriptor = lockName.withCString { name in
        Darwin.openat(
          directoryDescriptor,
          name,
          O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
          S_IRUSR | S_IWUSR
        )
      }
      guard lockDescriptor >= 0 else {
        throw StoreError.openFailed(
          path: directory.appendingPathComponent(lockName).path,
          code: errno
        )
      }
      try validateDescriptor(lockDescriptor, path: directory.appendingPathComponent(lockName).path)
      guard flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
        let code = errno
        if code == EWOULDBLOCK || code == EAGAIN {
          throw StoreError.writerAlreadyActive(
            path: directory.appendingPathComponent(lockName).path
          )
        }
        throw StoreError.openFailed(
          path: directory.appendingPathComponent(lockName).path,
          code: code
        )
      }

      let segments = try segmentIndices(
        directory: directory,
        workerAttemptIdentity: workerAttemptIdentity
      )
      let segmentIndex = segments.last ?? 0
      if !segments.isEmpty {
        try requireContiguousSegments(segments)
      }
      let journalName = artifactFileName(
        for: workerAttemptIdentity,
        segmentIndex: segmentIndex
      )
      journalDescriptor = journalName.withCString { name in
        Darwin.openat(
          directoryDescriptor,
          name,
          O_RDWR | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW,
          S_IRUSR | S_IWUSR
        )
      }
      guard journalDescriptor >= 0 else {
        throw StoreError.openFailed(
          path: directory.appendingPathComponent(journalName).path,
          code: errno
        )
      }
      let journalPath = directory.appendingPathComponent(journalName).path
      try validateDescriptor(journalDescriptor, path: journalPath)
      let journalByteCount = try repairTornTail(
        descriptor: journalDescriptor,
        path: journalPath,
        directoryDescriptor: directoryDescriptor
      )
      let sequence = try artifact(
        in: artifactRoot,
        expectedWorkerAttemptIdentity: workerAttemptIdentity
      )?.sequence ?? 0
      return WriterSetup(
        directory: directory,
        directoryDescriptor: directoryDescriptor,
        lockDescriptor: lockDescriptor,
        journalDescriptor: journalDescriptor,
        segmentIndex: segmentIndex,
        journalByteCount: journalByteCount,
        sequence: sequence
      )
    } catch {
      if journalDescriptor >= 0 { Darwin.close(journalDescriptor) }
      if lockDescriptor >= 0 {
        _ = flock(lockDescriptor, LOCK_UN)
        Darwin.close(lockDescriptor)
      }
      Darwin.close(directoryDescriptor)
      throw error
    }
  }

  private func repairTornTail(
    descriptor: Int32,
    path: String,
    directoryDescriptor: Int32
  ) throws -> Int64 {
    var status = stat()
    guard fstat(descriptor, &status) == 0 else {
      throw StoreError.readFailed(path: path, reason: "fstat errno=\(errno)")
    }
    guard status.st_size > 0 else { return 0 }
    var finalByte: UInt8 = 0
    let finalRead = withUnsafeMutableBytes(of: &finalByte) { buffer in
      Darwin.pread(descriptor, buffer.baseAddress, 1, status.st_size - 1)
    }
    guard finalRead == 1 else {
      throw StoreError.readFailed(path: path, reason: "pread errno=\(errno)")
    }
    guard finalByte != 0x0A else { return status.st_size }

    var scanEnd = status.st_size
    var completeByteCount: Int64 = 0
    let chunkSize = 65_536
    while scanEnd > 0 {
      let readCount = min(Int64(chunkSize), scanEnd)
      let readOffset = scanEnd - readCount
      var buffer = Data(count: Int(readCount))
      let count = buffer.withUnsafeMutableBytes { bytes in
        Darwin.pread(descriptor, bytes.baseAddress, Int(readCount), readOffset)
      }
      guard count == Int(readCount) else {
        throw StoreError.readFailed(path: path, reason: "pread errno=\(errno)")
      }
      if let newline = buffer.lastIndex(of: 0x0A) {
        completeByteCount = readOffset + Int64(buffer.distance(from: buffer.startIndex, to: newline)) + 1
        break
      }
      scanEnd = readOffset
    }
    guard ftruncate(descriptor, completeByteCount) == 0 else {
      throw StoreError.writeFailed(path: path, reason: "ftruncate errno=\(errno)")
    }
    guard fsync(descriptor) == 0 else {
      throw StoreError.syncFailed(path: path, code: errno)
    }
    guard fsync(directoryDescriptor) == 0 else {
      throw StoreError.syncFailed(path: path, code: errno)
    }
    return completeByteCount
  }

  private func validated(
    _ artifact: TrainingRunWorkerProgressArtifact,
    expectedWorkerAttemptIdentity: TrainingRunWorkerAttemptIdentity
  ) throws {
    do {
      try artifact.validate(
        expectedWorkerAttemptIdentity: expectedWorkerAttemptIdentity
      )
    } catch let error as TrainingRunWorkerProgressArtifact.ValidationError {
      throw StoreError.invalidArtifact(error)
    }
  }

  private func encodedData(
    _ artifact: TrainingRunWorkerProgressArtifact,
    path: String
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    do {
      return try encoder.encode(artifact)
    } catch {
      throw StoreError.writeFailed(path: path, reason: String(describing: error))
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

  private func directoryURL(in artifactRoot: URL) -> URL {
    artifactRoot.appendingPathComponent(
      TrainingRunWorkerProgressArtifact.directoryName,
      isDirectory: true
    )
  }

  private func artifactFileName(
    for identity: TrainingRunWorkerAttemptIdentity,
    segmentIndex: UInt64
  ) -> String {
    let segment = String(format: "%016llx", segmentIndex)
    return "\(identity.launchID.uuidString).\(identity.attemptID.uuidString).\(segment).jsonl"
  }

  private func writerLockFileName(
    for identity: TrainingRunWorkerAttemptIdentity
  ) -> String {
    "\(identity.launchID.uuidString).\(identity.attemptID.uuidString).writer.lock"
  }

  private func segmentIndices(
    directory: URL,
    workerAttemptIdentity: TrainingRunWorkerAttemptIdentity
  ) throws -> [UInt64] {
    let prefix = "\(workerAttemptIdentity.launchID.uuidString).\(workerAttemptIdentity.attemptID.uuidString)."
    let suffix = ".jsonl"
    let names: [String]
    do {
      names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    } catch {
      throw StoreError.readFailed(path: directory.path, reason: String(describing: error))
    }
    var indices: [UInt64] = []
    for name in names where name.hasPrefix(prefix) && name.hasSuffix(suffix) {
      let start = name.index(name.startIndex, offsetBy: prefix.count)
      let end = name.index(name.endIndex, offsetBy: -suffix.count)
      let encoded = String(name[start..<end])
      guard encoded.count == 16, let index = UInt64(encoded, radix: 16) else {
        throw StoreError.invalidJournalSegment(name)
      }
      indices.append(index)
    }
    return indices.sorted()
  }

  private func requireContiguousSegments(_ segments: [UInt64]) throws {
    for (offset, segment) in segments.enumerated() where segment != UInt64(offset) {
      throw StoreError.missingJournalSegment(index: UInt64(offset))
    }
  }

  private func prepareDirectory(_ directory: URL) throws {
    var status = stat()
    let existing = directory.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return lstat(path, &status)
    }
    if existing != 0 {
      guard errno == ENOENT else {
        throw StoreError.openFailed(path: directory.path, code: errno)
      }
      do {
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700]
        )
      } catch {
        throw StoreError.writeFailed(
          path: directory.path,
          reason: String(describing: error)
        )
      }
      let result = directory.withUnsafeFileSystemRepresentation { path in
        guard let path else { return Int32(-1) }
        return lstat(path, &status)
      }
      guard result == 0 else {
        throw StoreError.openFailed(path: directory.path, code: errno)
      }
    }
    guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
      throw StoreError.unsafeDirectory(directory.path)
    }
    guard status.st_uid == geteuid() else {
      throw StoreError.unexpectedOwner(
        path: directory.path,
        expected: geteuid(),
        actual: status.st_uid
      )
    }
    do {
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: directory.path
      )
    } catch {
      throw StoreError.writeFailed(
        path: directory.path,
        reason: String(describing: error)
      )
    }
  }

  private func validateDirectoryDescriptor(_ descriptor: Int32, path: String) throws {
    var status = stat()
    guard fstat(descriptor, &status) == 0 else {
      throw StoreError.readFailed(path: path, reason: "fstat errno=\(errno)")
    }
    guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
      throw StoreError.unsafeDirectory(path)
    }
    try validateTrustMetadata(status, path: path)
  }

  private func validateDescriptor(_ descriptor: Int32, path: String) throws {
    var status = stat()
    guard fstat(descriptor, &status) == 0 else {
      throw StoreError.readFailed(path: path, reason: "fstat errno=\(errno)")
    }
    try validateFileStatus(status, path: path)
  }

  private func validateFileStatus(_ status: stat, path: String) throws {
    guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
      throw StoreError.unsafeFile(path)
    }
    try validateTrustMetadata(status, path: path)
  }

  private func validateTrustMetadata(_ status: stat, path: String) throws {
    guard status.st_uid == geteuid() else {
      throw StoreError.unexpectedOwner(
        path: path,
        expected: geteuid(),
        actual: status.st_uid
      )
    }
    let permissions = status.st_mode & mode_t(0o777)
    guard permissions & mode_t(0o077) == 0 else {
      throw StoreError.unsafePermissions(path: path, mode: UInt16(permissions))
    }
  }
}
