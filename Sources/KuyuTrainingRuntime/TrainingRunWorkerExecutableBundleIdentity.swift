import CryptoKit
import Darwin
import Foundation

struct TrainingRunWorkerExecutableBundleIdentity: Sendable, Equatable {
  enum IdentityError: Error, Sendable, Equatable {
    case invalidRoot(String)
    case inspectionFailed(path: String, code: Int32)
    case rootIsNotDirectory(String)
    case enumerationFailed(path: String, reason: String)
    case symbolicLink(String)
    case unsupportedEntry(String)
    case emptyBundle(String)
    case fileReadFailed(path: String, reason: String)
    case byteCountOverflow(String)
  }

  let fileCount: Int
  let byteCount: Int
  let sha256Digest: String

  private struct Entry {
    let relativePath: String
    let url: URL
    let isDirectory: Bool
  }

  static func validated(
    _ requestedRootURL: URL
  ) throws -> TrainingRunWorkerExecutableBundleIdentity {
    guard requestedRootURL.isFileURL,
      requestedRootURL.path.hasPrefix("/")
    else {
      throw IdentityError.invalidRoot(requestedRootURL.absoluteString)
    }
    let root = requestedRootURL.standardizedFileURL
    let rootStatus = try status(at: root)
    guard rootStatus.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
      throw IdentityError.rootIsNotDirectory(root.path)
    }
    var entries = try entries(in: root)
    guard entries.contains(where: { !$0.isDirectory }) else {
      throw IdentityError.emptyBundle(root.path)
    }

    entries.sort { $0.relativePath < $1.relativePath }
    var hasher = SHA256()
    var totalByteCount = 0
    var fileCount = 0
    for entry in entries {
      try Task.checkCancellation()
      hasher.update(data: Data(entry.relativePath.utf8))
      hasher.update(data: Data([0]))
      if entry.isDirectory {
        hasher.update(data: Data([0x44, 0]))
        continue
      }
      let data: Data
      do {
        data = try Data(contentsOf: entry.url, options: [.mappedIfSafe])
      } catch {
        throw IdentityError.fileReadFailed(
          path: entry.url.path,
          reason: String(describing: error)
        )
      }
      let (nextByteCount, overflow) = totalByteCount.addingReportingOverflow(
        data.count
      )
      guard !overflow else {
        throw IdentityError.byteCountOverflow(root.path)
      }
      totalByteCount = nextByteCount
      fileCount += 1
      hasher.update(data: Data([0x46, 0]))
      hasher.update(data: data)
      hasher.update(data: Data([0]))
    }

    return TrainingRunWorkerExecutableBundleIdentity(
      fileCount: fileCount,
      byteCount: totalByteCount,
      sha256Digest: hasher.finalize().map {
        String(format: "%02x", $0)
      }.joined()
    )
  }

  private static func status(at url: URL) throws -> stat {
    var status = stat()
    let result = url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return lstat(path, &status)
    }
    guard result == 0 else {
      throw IdentityError.inspectionFailed(path: url.path, code: errno)
    }
    return status
  }

  private static func entries(
    in root: URL
  ) throws -> [Entry] {
    var directories: [(relativePath: String, url: URL)] = [("", root)]
    var entries: [Entry] = []
    while let directory = directories.popLast() {
      try Task.checkCancellation()
      let names: [String]
      do {
        names = try FileManager.default.contentsOfDirectory(
          atPath: directory.url.path
        )
      } catch {
        throw IdentityError.enumerationFailed(
          path: directory.url.path,
          reason: String(describing: error)
        )
      }
      for name in names.sorted() {
        let relativePath = directory.relativePath.isEmpty
          ? name
          : directory.relativePath + "/" + name
        let entry = root.appendingPathComponent(
          relativePath,
          isDirectory: false
        )
        let entryStatus = try status(at: entry)
        let fileType = entryStatus.st_mode & mode_t(S_IFMT)
        if fileType == mode_t(S_IFLNK) {
          throw IdentityError.symbolicLink(entry.path)
        }
        if fileType == mode_t(S_IFDIR) {
          entries.append(
            Entry(
              relativePath: relativePath,
              url: entry,
              isDirectory: true
            )
          )
          directories.append((relativePath, entry))
          continue
        }
        guard fileType == mode_t(S_IFREG) else {
          throw IdentityError.unsupportedEntry(entry.path)
        }
        entries.append(
          Entry(
            relativePath: relativePath,
            url: entry,
            isDirectory: false
          )
        )
      }
    }
    return entries
  }
}
