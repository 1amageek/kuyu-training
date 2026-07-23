import Darwin
import Foundation

public struct POSIXTrainingRunWorkerSourceSnapshotCloner:
  TrainingRunWorkerSourceSnapshotCloning, Sendable
{
  public enum CloneError: Error, Sendable, Equatable {
    case failed(code: Int32)
  }

  public init() {}

  public func clone(source: URL, destination: URL) throws {
    let result = source.withUnsafeFileSystemRepresentation { sourcePath in
      destination.withUnsafeFileSystemRepresentation { destinationPath in
        guard let sourcePath, let destinationPath else { return Int32(-1) }
        return clonefile(sourcePath, destinationPath, UInt32(CLONE_NOFOLLOW_ANY))
      }
    }
    guard result == 0 else {
      throw CloneError.failed(code: errno)
    }
  }
}
