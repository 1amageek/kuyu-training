import CryptoKit
import Darwin
import Foundation

struct TrainingRunWorkerExecutableIdentity: Sendable, Equatable {
  enum IdentityError: Error, Sendable, Equatable {
    case invalidPath(String)
    case openFailed(path: String, code: Int32)
    case inspectionFailed(path: String, code: Int32)
    case readFailed(path: String, code: Int32)
    case notExecutable(path: String)
  }

  let device: dev_t
  let inode: ino_t
  let byteCount: off_t
  let modificationSeconds: Int64
  let modificationNanoseconds: Int64
  let changeSeconds: Int64
  let changeNanoseconds: Int64
  let sha256Digest: String

  static func validated(
    _ requestedURL: URL
  ) throws -> (url: URL, identity: TrainingRunWorkerExecutableIdentity) {
    guard requestedURL.isFileURL, requestedURL.path.hasPrefix("/") else {
      throw IdentityError.invalidPath(requestedURL.absoluteString)
    }
    let url = requestedURL.standardizedFileURL
    let descriptor = url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else {
      throw IdentityError.openFailed(path: url.path, code: errno)
    }
    defer { Darwin.close(descriptor) }
    var status = stat()
    guard fstat(descriptor, &status) == 0 else {
      throw IdentityError.inspectionFailed(path: url.path, code: errno)
    }
    guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
      status.st_mode & mode_t(0o111) != 0,
      Darwin.access(url.path, X_OK) == 0
    else {
      throw IdentityError.notExecutable(path: url.path)
    }
    let sha256Digest = try digest(descriptor: descriptor, path: url.path)
    return (
      url,
      TrainingRunWorkerExecutableIdentity(
        device: status.st_dev,
        inode: status.st_ino,
        byteCount: status.st_size,
        modificationSeconds: Int64(status.st_mtimespec.tv_sec),
        modificationNanoseconds: Int64(status.st_mtimespec.tv_nsec),
        changeSeconds: Int64(status.st_ctimespec.tv_sec),
        changeNanoseconds: Int64(status.st_ctimespec.tv_nsec),
        sha256Digest: sha256Digest
      )
    )
  }

  private static func digest(descriptor: Int32, path: String) throws -> String {
    var hasher = SHA256()
    var buffer = [UInt8](repeating: 0, count: 65_536)
    while true {
      let count = buffer.withUnsafeMutableBytes { bytes in
        Darwin.read(descriptor, bytes.baseAddress, bytes.count)
      }
      if count < 0 {
        if errno == EINTR { continue }
        throw IdentityError.readFailed(path: path, code: errno)
      }
      guard count > 0 else { break }
      hasher.update(data: Data(buffer.prefix(count)))
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
