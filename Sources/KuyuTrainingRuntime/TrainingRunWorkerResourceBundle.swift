import Foundation

public struct TrainingRunWorkerResourceBundle: Sendable, Equatable {
  public let sourceURL: URL

  public init(sourceURL: URL) {
    self.sourceURL = sourceURL
  }
}
