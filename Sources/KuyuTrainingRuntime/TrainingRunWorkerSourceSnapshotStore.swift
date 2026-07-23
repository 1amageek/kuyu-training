import Darwin
import Foundation
import KuyuTrainingContracts

public struct TrainingRunWorkerSourceSnapshotStore: Sendable {
  public enum SnapshotError: Error, Sendable, Equatable {
    case missingSourceBundle
    case unsupportedResumeSource(String)
    case snapshotAlreadyExists(String)
    case invalidContinuationRoot(String)
    case unsafeContinuationRoot(String)
    case unexpectedContinuationRootOwner(path: String, expected: UInt32, actual: UInt32)
    case unsafeContinuationRootPermissions(path: String, mode: UInt16)
    case continuationRootCreationFailed(path: String, reason: String)
    case continuationRootCleanupFailed(path: String, primary: String, cleanup: String)
    case canonicalizationFailed(path: String, code: Int32)
    case cloneFailed(source: String, destination: String, code: Int32)
    case copyFailed(source: String, destination: String, reason: String)
    case digestMismatch(expected: String, actual: String)
    case permissionUpdateFailed(path: String, reason: String)
  }

  public static let snapshotDirectoryName =
    TrainingRunArtifactLayout.sourceSnapshotDirectoryName
  public static let continuationDirectoryName =
    TrainingRunArtifactLayout.continuationDirectoryName

  private let cloner: any TrainingRunWorkerSourceSnapshotCloning

  public init(
    cloner: any TrainingRunWorkerSourceSnapshotCloning =
      POSIXTrainingRunWorkerSourceSnapshotCloner()
  ) {
    self.cloner = cloner
  }

  public func durableArtifact(
    _ artifact: TrainingRunWorkerLaunchArtifact
  ) throws -> TrainingRunWorkerLaunchArtifact {
    let artifactRoot = artifact.operation.artifactRoot
    try prepareArtifactRoot(artifactRoot)
    let sourceReference = try sourceReference(in: artifact)
    if artifactOwnedURL(sourceReference, in: artifactRoot) != nil {
      return try artifactByTransformingSource(artifact) { reference in
        try artifactOwnedReference(reference, in: artifactRoot)
      }
    }
    let continuationRoot = artifactRoot.appendingPathComponent(
      Self.continuationDirectoryName,
      isDirectory: true
    )
    if FileManager.default.fileExists(atPath: continuationRoot.path) {
      try requireOwnedDirectory(continuationRoot, privateAccessRequired: true)
      return try artifactByTransformingSource(artifact) { reference in
        try existingSnapshot(reference, in: continuationRoot)
      }
    }
    do {
      try FileManager.default.createDirectory(
        at: continuationRoot,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      try requireOwnedDirectory(continuationRoot, privateAccessRequired: true)
      return try materializedArtifact(artifact, in: continuationRoot)
    } catch {
      let primaryError = error
      do {
        if FileManager.default.fileExists(atPath: continuationRoot.path) {
          try prepareForRemoval(continuationRoot)
          try FileManager.default.removeItem(at: continuationRoot)
        }
      } catch {
        throw SnapshotError.continuationRootCleanupFailed(
          path: continuationRoot.path,
          primary: String(describing: primaryError),
          cleanup: String(describing: error)
        )
      }
      if let snapshotError = primaryError as? SnapshotError {
        throw snapshotError
      }
      throw SnapshotError.continuationRootCreationFailed(
        path: continuationRoot.path,
        reason: String(describing: primaryError)
      )
    }
  }

  public func materializedArtifact(
    _ artifact: TrainingRunWorkerLaunchArtifact,
    in launchDirectory: URL
  ) throws -> TrainingRunWorkerLaunchArtifact {
    try artifactByTransformingSource(artifact) { reference in
      try snapshot(reference, in: launchDirectory)
    }
  }

  private func artifactByTransformingSource(
    _ artifact: TrainingRunWorkerLaunchArtifact,
    transform: (ModelBundleReference) throws -> ModelBundleReference
  ) throws -> TrainingRunWorkerLaunchArtifact {
    try Task.checkCancellation()
    let operation: TrainingRunWorkerOperation
    switch artifact.operation {
    case .start(let request):
      guard let sourceBundle = request.sourceBundle else {
        throw SnapshotError.missingSourceBundle
      }
      operation = .start(
        TrainingRunRequest(
          runID: request.runID,
          projectRoot: request.projectRoot,
          artifactRoot: request.artifactRoot,
          taskProfileID: request.taskProfileID,
          policyContract: request.policyContract,
          actionContract: request.actionContract,
          sourceBundle: try transform(sourceBundle),
          seedCount: request.seedCount,
          populationSize: request.populationSize,
          generationLimit: request.generationLimit,
          configuration: request.configuration
        )
      )
    case .resume(let request):
      let source: TrainingResumeSource
      switch request.source {
      case .artifactRoot(let artifactRoot):
        throw SnapshotError.unsupportedResumeSource(artifactRoot.path)
      case .checkpoint(let checkpoint):
        source = .checkpoint(try transform(checkpoint))
      case .continuation(let continuation):
        source = .continuation(
          TrainingContinuationResumeSource(
            artifactRoot: continuation.artifactRoot,
            checkpoint: try transform(continuation.checkpoint)
          )
        )
      }
      operation = .resume(
        TrainingResumeRequest(
          runID: request.runID,
          source: source,
          destinationArtifactRoot: request.destinationArtifactRoot,
          projectRoot: request.projectRoot,
          taskProfileID: request.taskProfileID,
          policyContract: request.policyContract,
          actionContract: request.actionContract,
          seedCount: request.seedCount,
          populationSize: request.populationSize,
          generationLimit: request.generationLimit,
          configuration: request.configuration
        )
      )
    }
    try Task.checkCancellation()
    return TrainingRunWorkerLaunchArtifact(
      launchID: artifact.launchID,
      attemptID: artifact.attemptID,
      createdAt: artifact.createdAt,
      operation: operation
    )
  }

  private func existingSnapshot(
    _ reference: ModelBundleReference,
    in continuationRoot: URL
  ) throws -> ModelBundleReference {
    guard let expectedDigest = reference.contentHash else {
      throw TrainingRunWorkerSourceIntegrityVerifier.VerificationError.missingSourceDigest(
        bundleID: reference.bundleID
      )
    }
    let snapshotURL = continuationRoot.appendingPathComponent(
      Self.snapshotDirectoryName,
      isDirectory: true
    )
    let pinned = try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [continuationRoot]
    ).pinnedReference(
      ModelBundleReference(
        bundleID: reference.bundleID,
        kind: reference.kind,
        url: snapshotURL,
        provenanceURL: reference.provenanceURL ?? reference.url,
        robotManifestID: reference.robotManifestID,
        observationSchemaID: reference.observationSchemaID,
        actionSchemaID: reference.actionSchemaID
      )
    )
    guard pinned.contentHash == expectedDigest.lowercased() else {
      throw SnapshotError.digestMismatch(
        expected: expectedDigest.lowercased(),
        actual: pinned.contentHash ?? "missing"
      )
    }
    return pinned
  }

  private func sourceReference(
    in artifact: TrainingRunWorkerLaunchArtifact
  ) throws -> ModelBundleReference {
    switch artifact.operation {
    case .start(let request):
      guard let sourceBundle = request.sourceBundle else {
        throw SnapshotError.missingSourceBundle
      }
      return sourceBundle
    case .resume(let request):
      switch request.source {
      case .artifactRoot(let artifactRoot):
        throw SnapshotError.unsupportedResumeSource(artifactRoot.path)
      case .checkpoint(let checkpoint):
        return checkpoint
      case .continuation(let continuation):
        return continuation.checkpoint
      }
    }
  }

  private func artifactOwnedReference(
    _ reference: ModelBundleReference,
    in artifactRoot: URL
  ) throws -> ModelBundleReference {
    guard let expectedDigest = reference.contentHash else {
      throw TrainingRunWorkerSourceIntegrityVerifier.VerificationError.missingSourceDigest(
        bundleID: reference.bundleID
      )
    }
    guard let artifactOwnedURL = artifactOwnedURL(reference, in: artifactRoot) else {
      throw SnapshotError.invalidContinuationRoot(reference.url.path)
    }
    let pinned = try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [artifactRoot]
    ).pinnedReference(
      ModelBundleReference(
        bundleID: reference.bundleID,
        kind: reference.kind,
        url: artifactOwnedURL,
        provenanceURL: reference.provenanceURL,
        robotManifestID: reference.robotManifestID,
        observationSchemaID: reference.observationSchemaID,
        actionSchemaID: reference.actionSchemaID
      )
    )
    guard pinned.contentHash == expectedDigest.lowercased() else {
      throw SnapshotError.digestMismatch(
        expected: expectedDigest.lowercased(),
        actual: pinned.contentHash ?? "missing"
      )
    }
    return pinned
  }

  private func artifactOwnedURL(
    _ reference: ModelBundleReference,
    in artifactRoot: URL
  ) -> URL? {
    if isDescendant(reference.url, of: artifactRoot) {
      return reference.url
    }
    if let provenanceURL = reference.provenanceURL,
      isDescendant(provenanceURL, of: artifactRoot)
    {
      return provenanceURL
    }
    return nil
  }

  private func isDescendant(_ url: URL, of root: URL) -> Bool {
    let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
    let sourcePath = url.standardizedFileURL.resolvingSymlinksInPath().path
    return sourcePath.hasPrefix(rootPath + "/")
  }

  private func snapshot(
    _ reference: ModelBundleReference,
    in launchDirectory: URL
  ) throws -> ModelBundleReference {
    guard let expectedDigest = reference.contentHash else {
      throw TrainingRunWorkerSourceIntegrityVerifier.VerificationError.missingSourceDigest(
        bundleID: reference.bundleID
      )
    }
    let destination = launchDirectory.appendingPathComponent(
      Self.snapshotDirectoryName,
      isDirectory: true
    )
    guard !FileManager.default.fileExists(atPath: destination.path) else {
      throw SnapshotError.snapshotAlreadyExists(destination.path)
    }
    let canonicalSource = try canonicalExistingPath(reference.url)
    let canonicalDestination = try canonicalExistingPath(launchDirectory)
      .appendingPathComponent(Self.snapshotDirectoryName, isDirectory: true)
    do {
      try cloner.clone(source: canonicalSource, destination: canonicalDestination)
    } catch let error as POSIXTrainingRunWorkerSourceSnapshotCloner.CloneError {
      guard case .failed(let code) = error else { throw error }
      if Self.supportsCopyFallback(for: code) {
        do {
          try FileManager.default.copyItem(
            at: canonicalSource,
            to: canonicalDestination
          )
        } catch {
          throw SnapshotError.copyFailed(
            source: reference.url.path,
            destination: destination.path,
            reason: String(describing: error)
          )
        }
      } else {
        throw SnapshotError.cloneFailed(
          source: reference.url.path,
          destination: destination.path,
          code: code
        )
      }
    } catch {
      throw SnapshotError.copyFailed(
        source: reference.url.path,
        destination: destination.path,
        reason: String(describing: error)
      )
    }
    try makeReadOnly(destination)
    let pinned = try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [launchDirectory]
    ).pinnedReference(
        ModelBundleReference(
        bundleID: reference.bundleID,
        kind: reference.kind,
        url: destination,
        provenanceURL: reference.provenanceURL ?? reference.url,
        robotManifestID: reference.robotManifestID,
        observationSchemaID: reference.observationSchemaID,
        actionSchemaID: reference.actionSchemaID
      )
    )
    guard pinned.contentHash == expectedDigest.lowercased() else {
      throw SnapshotError.digestMismatch(
        expected: expectedDigest.lowercased(),
        actual: pinned.contentHash ?? "missing"
      )
    }
    return pinned
  }

  private static func supportsCopyFallback(for code: Int32) -> Bool {
    code == EXDEV || code == ENOTSUP || code == ENOSYS
  }

  private func prepareArtifactRoot(_ artifactRoot: URL) throws {
    guard artifactRoot.isFileURL, artifactRoot.path.hasPrefix("/") else {
      throw SnapshotError.invalidContinuationRoot(artifactRoot.absoluteString)
    }
    if !FileManager.default.fileExists(atPath: artifactRoot.path) {
      do {
        try FileManager.default.createDirectory(
          at: artifactRoot,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700]
        )
      } catch {
        throw SnapshotError.continuationRootCreationFailed(
          path: artifactRoot.path,
          reason: String(describing: error)
        )
      }
    }
    try requireOwnedDirectory(artifactRoot, privateAccessRequired: false)
  }

  private func requireOwnedDirectory(
    _ url: URL,
    privateAccessRequired: Bool
  ) throws {
    var status = stat()
    let result = url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return lstat(path, &status)
    }
    guard result == 0 else {
      throw SnapshotError.invalidContinuationRoot(url.path)
    }
    guard status.st_mode & mode_t(S_IFMT) != mode_t(S_IFLNK) else {
      throw SnapshotError.unsafeContinuationRoot(url.path)
    }
    guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
      throw SnapshotError.invalidContinuationRoot(url.path)
    }
    guard status.st_uid == geteuid() else {
      throw SnapshotError.unexpectedContinuationRootOwner(
        path: url.path,
        expected: geteuid(),
        actual: status.st_uid
      )
    }
    let permissions = status.st_mode & mode_t(0o777)
    let forbidden = privateAccessRequired ? mode_t(0o077) : mode_t(0o022)
    guard permissions & forbidden == 0 else {
      throw SnapshotError.unsafeContinuationRootPermissions(
        path: url.path,
        mode: UInt16(permissions)
      )
    }
  }

  private func prepareForRemoval(_ root: URL) throws {
    guard chmod(root.path, S_IRWXU) == 0 else {
      throw SnapshotError.permissionUpdateFailed(
        path: root.path,
        reason: "cleanup chmod errno=\(errno)"
      )
    }
    var enumerationFailure: String?
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
      options: [],
      errorHandler: { url, error in
        enumerationFailure = "\(url.path): \(error)"
        return false
      }
    ) else {
      throw SnapshotError.permissionUpdateFailed(path: root.path, reason: "cleanup enumeration")
    }
    var entries: [URL] = []
    for case let entry as URL in enumerator {
      entries.append(entry)
    }
    if let enumerationFailure {
      throw SnapshotError.permissionUpdateFailed(
        path: root.path,
        reason: enumerationFailure
      )
    }
    for entry in entries.reversed() {
      var status = stat()
      let result = entry.withUnsafeFileSystemRepresentation { path in
        guard let path else { return Int32(-1) }
        return lstat(path, &status)
      }
      guard result == 0 else {
        throw SnapshotError.permissionUpdateFailed(
          path: entry.path,
          reason: "cleanup lstat errno=\(errno)"
        )
      }
      let fileType = status.st_mode & mode_t(S_IFMT)
      if fileType == mode_t(S_IFDIR) {
        guard chmod(entry.path, S_IRWXU) == 0 else {
          throw SnapshotError.permissionUpdateFailed(
            path: entry.path,
            reason: "cleanup chmod errno=\(errno)"
          )
        }
      } else if fileType == mode_t(S_IFREG) {
        guard chmod(entry.path, S_IRUSR | S_IWUSR) == 0 else {
          throw SnapshotError.permissionUpdateFailed(
            path: entry.path,
            reason: "cleanup chmod errno=\(errno)"
          )
        }
      } else {
        throw SnapshotError.permissionUpdateFailed(
          path: entry.path,
          reason: "cleanup unsupported entry"
        )
      }
    }
  }

  private func canonicalExistingPath(_ url: URL) throws -> URL {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    let didResolve = url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return false }
      return realpath(path, &buffer) != nil
    }
    guard didResolve else {
      throw SnapshotError.canonicalizationFailed(path: url.path, code: errno)
    }
    let terminator = buffer.firstIndex(of: 0) ?? buffer.endIndex
    let path = String(
      decoding: buffer[..<terminator].map { UInt8(bitPattern: $0) },
      as: UTF8.self
    )
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  private func makeReadOnly(_ root: URL) throws {
    var enumerationFailure: String?
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
      options: [],
      errorHandler: { url, error in
        enumerationFailure = "\(url.path): \(error)"
        return false
      }
    ) else {
      throw SnapshotError.permissionUpdateFailed(path: root.path, reason: "enumeration failed")
    }
    var entries: [URL] = []
    for case let entry as URL in enumerator {
      try Task.checkCancellation()
      entries.append(entry)
    }
    if let enumerationFailure {
      throw SnapshotError.permissionUpdateFailed(
        path: root.path,
        reason: enumerationFailure
      )
    }
    for entry in entries.reversed() {
      let values = try entry.resourceValues(
        forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
      )
      guard values.isSymbolicLink != true else {
        throw SnapshotError.permissionUpdateFailed(path: entry.path, reason: "symbolic link")
      }
      let permissions: Int
      if values.isDirectory == true {
        permissions = 0o500
      } else if values.isRegularFile == true {
        permissions = 0o400
      } else {
        throw SnapshotError.permissionUpdateFailed(path: entry.path, reason: "unsupported entry")
      }
      do {
        try FileManager.default.setAttributes(
          [.posixPermissions: permissions],
          ofItemAtPath: entry.path
        )
      } catch {
        throw SnapshotError.permissionUpdateFailed(
          path: entry.path,
          reason: String(describing: error)
        )
      }
    }
    do {
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o500],
        ofItemAtPath: root.path
      )
    } catch {
      throw SnapshotError.permissionUpdateFailed(
        path: root.path,
        reason: String(describing: error)
      )
    }
  }
}
