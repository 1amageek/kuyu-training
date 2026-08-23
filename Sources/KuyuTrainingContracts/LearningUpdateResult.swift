public struct LearningUpdateResult: Sendable, Codable, Equatable {
  public let runID: TrainingRunID
  public let source: LearningUpdateSourceIdentity
  public let transitionCount: Int
  public let metrics: LearningUpdateMetrics
  public let candidate: ModelBundleReference

  public init(
    runID: TrainingRunID,
    source: LearningUpdateSourceIdentity,
    transitionCount: Int,
    metrics: LearningUpdateMetrics,
    candidate: ModelBundleReference
  ) {
    self.runID = runID
    self.source = source
    self.transitionCount = transitionCount
    self.metrics = metrics
    self.candidate = candidate
  }
}
