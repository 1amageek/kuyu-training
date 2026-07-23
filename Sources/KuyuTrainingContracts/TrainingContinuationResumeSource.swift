import Foundation

public struct TrainingContinuationResumeSource: Sendable, Codable, Equatable {
  public let artifactRoot: URL
  public let checkpoint: ModelBundleReference

  public init(
    artifactRoot: URL,
    checkpoint: ModelBundleReference
  ) {
    self.artifactRoot = artifactRoot
    self.checkpoint = checkpoint
  }
}
