import Foundation

public struct LearningUpdateRequest: Sendable, Codable, Equatable {
  public let runID: TrainingRunID
  public let datasetURL: URL
  public let sourceBundle: ModelBundleReference
  public let candidateBundleID: String
  public let candidateBundleURL: URL
  public let plan: LearningUpdatePlan

  public init(
    runID: TrainingRunID,
    datasetURL: URL,
    sourceBundle: ModelBundleReference,
    candidateBundleID: String,
    candidateBundleURL: URL,
    plan: LearningUpdatePlan
  ) {
    self.runID = runID
    self.datasetURL = datasetURL
    self.sourceBundle = sourceBundle
    self.candidateBundleID = candidateBundleID
    self.candidateBundleURL = candidateBundleURL
    self.plan = plan
  }
}
