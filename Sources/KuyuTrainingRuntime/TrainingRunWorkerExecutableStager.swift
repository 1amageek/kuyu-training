import Darwin
import Foundation
import KuyuEvolution

public struct TrainingRunWorkerExecutableStager: Sendable {
  public enum StageError: Error, Sendable, Equatable {
    case stagingDirectoryExists(String)
    case directoryCreationFailed(path: String, reason: String)
    case cloneFailed(source: String, destination: String, code: Int32)
    case copyFailed(source: String, destination: String, reason: String)
    case sourceChanged(String)
    case stagedExecutableMismatch(String)
    case duplicateResourceBundle(String)
    case invalidResourceBundle(path: String, reason: String)
    case resourceBundleChanged(String)
    case stagedResourceBundleMismatch(String)
    case unsupportedEntry(String)
    case unsafeSymbolicLink(String)
    case permissionUpdateFailed(path: String, code: Int32)
  }

  public static let stagingDirectoryName = "WORKER_EXECUTABLE"

  private struct Layout {
    let sourceRoot: URL
    let destinationRoot: URL
    let executableURL: URL
    let resourceBundleDirectory: URL
  }

  private struct PinnedResourceBundle {
    let sourceURL: URL
    let name: String
    let identity: EvolutionCheckpointReference
  }

  private let cloner: any TrainingRunWorkerSourceSnapshotCloning

  public init(
    cloner: any TrainingRunWorkerSourceSnapshotCloning =
      POSIXTrainingRunWorkerSourceSnapshotCloner()
  ) {
    self.cloner = cloner
  }

  func stage(
    sourceExecutableURL: URL,
    expectedIdentity: TrainingRunWorkerExecutableIdentity,
    resourceBundles: [TrainingRunWorkerResourceBundle] = [],
    in launchDirectory: URL
  ) throws -> URL {
    let pinnedResourceBundles = try pin(resourceBundles)
    let stagingDirectory = launchDirectory.appendingPathComponent(
      Self.stagingDirectoryName,
      isDirectory: true
    )
    guard !FileManager.default.fileExists(atPath: stagingDirectory.path) else {
      throw StageError.stagingDirectoryExists(stagingDirectory.path)
    }
    do {
      try FileManager.default.createDirectory(
        at: stagingDirectory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
    } catch {
      throw StageError.directoryCreationFailed(
        path: stagingDirectory.path,
        reason: String(describing: error)
      )
    }
    let layout = layout(
      sourceExecutableURL: sourceExecutableURL,
      stagingDirectory: stagingDirectory
    )
    try materialize(source: layout.sourceRoot, destination: layout.destinationRoot)
    if !pinnedResourceBundles.isEmpty {
      do {
        try FileManager.default.createDirectory(
          at: layout.resourceBundleDirectory,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700]
        )
      } catch {
        throw StageError.directoryCreationFailed(
          path: layout.resourceBundleDirectory.path,
          reason: String(describing: error)
        )
      }
    }
    for resource in pinnedResourceBundles {
      let destination = layout.resourceBundleDirectory.appendingPathComponent(
        resource.name,
        isDirectory: true
      )
      if !FileManager.default.fileExists(atPath: destination.path) {
        try materialize(source: resource.sourceURL, destination: destination)
      }
    }
    try makeReadOnly(stagingDirectory)

    let sourceAfterStaging = try TrainingRunWorkerExecutableIdentity.validated(
      sourceExecutableURL
    ).identity
    guard sourceAfterStaging == expectedIdentity else {
      throw StageError.sourceChanged(sourceExecutableURL.path)
    }
    let stagedIdentity = try TrainingRunWorkerExecutableIdentity.validated(
      layout.executableURL
    ).identity
    guard stagedIdentity.byteCount == expectedIdentity.byteCount,
      stagedIdentity.sha256Digest == expectedIdentity.sha256Digest
    else {
      throw StageError.stagedExecutableMismatch(layout.executableURL.path)
    }
    for resource in pinnedResourceBundles {
      let sourceAfterStaging = try resourceIdentity(
        at: resource.sourceURL,
        name: resource.name
      )
      guard Self.matches(sourceAfterStaging, resource.identity) else {
        throw StageError.resourceBundleChanged(resource.sourceURL.path)
      }
      let destination = layout.resourceBundleDirectory.appendingPathComponent(
        resource.name,
        isDirectory: true
      )
      let stagedResource = try resourceIdentity(at: destination, name: resource.name)
      guard Self.matches(stagedResource, resource.identity) else {
        throw StageError.stagedResourceBundleMismatch(destination.path)
      }
    }
    return layout.executableURL
  }

  func stagedExecutableURL(
    sourceExecutableURL: URL,
    in launchDirectory: URL
  ) -> URL {
    let stagingDirectory = launchDirectory.appendingPathComponent(
      Self.stagingDirectoryName,
      isDirectory: true
    )
    return layout(
      sourceExecutableURL: sourceExecutableURL,
      stagingDirectory: stagingDirectory
    ).executableURL
  }

  private func layout(
    sourceExecutableURL: URL,
    stagingDirectory: URL
  ) -> Layout {
    let executable = sourceExecutableURL.standardizedFileURL
    let macOSDirectory = executable.deletingLastPathComponent()
    let contentsDirectory = macOSDirectory.deletingLastPathComponent()
    let applicationBundle = contentsDirectory.deletingLastPathComponent()
    if macOSDirectory.lastPathComponent == "MacOS",
      contentsDirectory.lastPathComponent == "Contents",
      applicationBundle.pathExtension == "app"
    {
      let destinationBundle = stagingDirectory.appendingPathComponent(
        applicationBundle.lastPathComponent,
        isDirectory: true
      )
      return Layout(
        sourceRoot: applicationBundle,
        destinationRoot: destinationBundle,
        executableURL: destinationBundle
          .appendingPathComponent("Contents", isDirectory: true)
          .appendingPathComponent("MacOS", isDirectory: true)
          .appendingPathComponent(executable.lastPathComponent, isDirectory: false),
        resourceBundleDirectory: destinationBundle
          .appendingPathComponent("Contents", isDirectory: true)
          .appendingPathComponent("Resources", isDirectory: true)
      )
    }
    let destination = stagingDirectory.appendingPathComponent(
      "worker",
      isDirectory: false
    )
    return Layout(
      sourceRoot: executable,
      destinationRoot: destination,
      executableURL: destination,
      resourceBundleDirectory: stagingDirectory
    )
  }

  private func pin(
    _ resourceBundles: [TrainingRunWorkerResourceBundle]
  ) throws -> [PinnedResourceBundle] {
    var names = Set<String>()
    return try resourceBundles.map { resource in
      let source = resource.sourceURL.standardizedFileURL
      let name = source.lastPathComponent
      guard source.isFileURL,
        source.pathExtension == "bundle",
        !name.isEmpty,
        name != ".",
        name != ".."
      else {
        throw StageError.invalidResourceBundle(
          path: resource.sourceURL.absoluteString,
          reason: "expected a file URL ending in .bundle"
        )
      }
      guard names.insert(name.lowercased()).inserted else {
        throw StageError.duplicateResourceBundle(name)
      }
      return PinnedResourceBundle(
        sourceURL: source,
        name: name,
        identity: try resourceIdentity(at: source, name: name)
      )
    }
  }

  private func resourceIdentity(
    at url: URL,
    name: String
  ) throws -> EvolutionCheckpointReference {
    do {
      return try EvolutionCheckpointIntegrity().reference(
        checkpointID: name,
        checkpointURL: url,
        artifactRoot: url.deletingLastPathComponent()
      )
    } catch {
      throw StageError.invalidResourceBundle(
        path: url.path,
        reason: String(describing: error)
      )
    }
  }

  private static func matches(
    _ lhs: EvolutionCheckpointReference,
    _ rhs: EvolutionCheckpointReference
  ) -> Bool {
    lhs.sha256Digest == rhs.sha256Digest
      && lhs.fileCount == rhs.fileCount
      && lhs.byteCount == rhs.byteCount
  }

  private func materialize(source: URL, destination: URL) throws {
    do {
      try cloner.clone(source: source, destination: destination)
    } catch let error as POSIXTrainingRunWorkerSourceSnapshotCloner.CloneError {
      guard case .failed(let code) = error else { throw error }
      guard Self.supportsCopyFallback(for: code) else {
        throw StageError.cloneFailed(
          source: source.path,
          destination: destination.path,
          code: code
        )
      }
      do {
        try FileManager.default.copyItem(at: source, to: destination)
      } catch {
        throw StageError.copyFailed(
          source: source.path,
          destination: destination.path,
          reason: String(describing: error)
        )
      }
    } catch {
      throw StageError.copyFailed(
        source: source.path,
        destination: destination.path,
        reason: String(describing: error)
      )
    }
  }

  private func makeReadOnly(_ root: URL) throws {
    var rootStatus = stat()
    let rootResult = root.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return lstat(path, &rootStatus)
    }
    guard rootResult == 0 else {
      throw StageError.permissionUpdateFailed(path: root.path, code: errno)
    }
    let rootType = rootStatus.st_mode & mode_t(S_IFMT)
    if rootType == mode_t(S_IFREG) {
      let permissions: mode_t = rootStatus.st_mode & mode_t(0o111) == 0
        ? S_IRUSR
        : S_IRUSR | S_IXUSR
      guard Darwin.chmod(root.path, permissions) == 0 else {
        throw StageError.permissionUpdateFailed(path: root.path, code: errno)
      }
      return
    }
    guard rootType == mode_t(S_IFDIR) else {
      throw StageError.unsupportedEntry(root.path)
    }
    var enumerationFailure: Error?
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: nil,
      options: [],
      errorHandler: { _, error in
        enumerationFailure = error
        return false
      }
    ) else {
      throw StageError.unsupportedEntry(root.path)
    }
    var entries: [URL] = []
    for case let entry as URL in enumerator {
      entries.append(entry)
    }
    if let enumerationFailure {
      throw StageError.copyFailed(
        source: root.path,
        destination: root.path,
        reason: String(describing: enumerationFailure)
      )
    }
    for entry in entries.reversed() {
      var status = stat()
      let result = entry.withUnsafeFileSystemRepresentation { path in
        guard let path else { return Int32(-1) }
        return lstat(path, &status)
      }
      guard result == 0 else {
        throw StageError.permissionUpdateFailed(path: entry.path, code: errno)
      }
      let fileType = status.st_mode & mode_t(S_IFMT)
      if fileType == mode_t(S_IFLNK) {
        try validateSymbolicLink(entry, root: root)
        continue
      }
      let permissions: mode_t
      if fileType == mode_t(S_IFDIR) {
        permissions = S_IRUSR | S_IXUSR
      } else if fileType == mode_t(S_IFREG) {
        permissions = status.st_mode & mode_t(0o111) == 0
          ? S_IRUSR
          : S_IRUSR | S_IXUSR
      } else {
        throw StageError.unsupportedEntry(entry.path)
      }
      guard Darwin.chmod(entry.path, permissions) == 0 else {
        throw StageError.permissionUpdateFailed(path: entry.path, code: errno)
      }
    }
    guard Darwin.chmod(root.path, S_IRUSR | S_IXUSR) == 0 else {
      throw StageError.permissionUpdateFailed(path: root.path, code: errno)
    }
  }

  private func validateSymbolicLink(_ url: URL, root: URL) throws {
    let target: String
    do {
      target = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
    } catch {
      throw StageError.unsafeSymbolicLink(url.path)
    }
    guard !target.hasPrefix("/") else {
      throw StageError.unsafeSymbolicLink(url.path)
    }
    let resolved = url.deletingLastPathComponent()
      .appendingPathComponent(target)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
    let rootPrefix = canonicalRoot.path.hasSuffix("/")
      ? canonicalRoot.path
      : canonicalRoot.path + "/"
    guard resolved.path.hasPrefix(rootPrefix) else {
      throw StageError.unsafeSymbolicLink(url.path)
    }
  }

  private static func supportsCopyFallback(for code: Int32) -> Bool {
    code == EXDEV || code == ENOTSUP || code == ENOSYS || code == ELOOP
  }
}
