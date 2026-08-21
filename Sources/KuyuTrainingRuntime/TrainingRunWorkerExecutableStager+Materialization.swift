import Darwin
import Foundation

extension TrainingRunWorkerExecutableStager {
  func materialize(source: URL, destination: URL) throws {
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
    } catch let error as CancellationError {
      throw error
    } catch {
      throw StageError.copyFailed(
        source: source.path,
        destination: destination.path,
        reason: String(describing: error)
      )
    }
  }

  func makeReadOnly(_ root: URL) throws {
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
