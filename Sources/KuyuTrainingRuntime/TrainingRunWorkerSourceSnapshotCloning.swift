import Foundation

public protocol TrainingRunWorkerSourceSnapshotCloning: Sendable {
  func clone(source: URL, destination: URL) throws
}
