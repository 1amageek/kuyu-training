import Foundation

public enum TrainingResumeSource: Sendable, Codable, Equatable {
  case artifactRoot(URL)
  case checkpoint(ModelBundleReference)
  case continuation(TrainingContinuationResumeSource)

  private enum CodingKeys: String, CodingKey {
    case kind
    case artifactRoot
    case checkpoint
    case continuation
  }

  private enum Kind: String, Codable {
    case artifactRoot
    case checkpoint
    case continuation
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .artifactRoot:
      self = .artifactRoot(try container.decode(URL.self, forKey: .artifactRoot))
    case .checkpoint:
      self = .checkpoint(try container.decode(ModelBundleReference.self, forKey: .checkpoint))
    case .continuation:
      self = .continuation(
        try container.decode(TrainingContinuationResumeSource.self, forKey: .continuation)
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .artifactRoot(let artifactRoot):
      try container.encode(Kind.artifactRoot, forKey: .kind)
      try container.encode(artifactRoot, forKey: .artifactRoot)
    case .checkpoint(let checkpoint):
      try container.encode(Kind.checkpoint, forKey: .kind)
      try container.encode(checkpoint, forKey: .checkpoint)
    case .continuation(let continuation):
      try container.encode(Kind.continuation, forKey: .kind)
      try container.encode(continuation, forKey: .continuation)
    }
  }
}

public struct TrainingResumeRequest: Sendable, Codable, Equatable {
  public let runID: TrainingRunID
  public let source: TrainingResumeSource
  public let destinationArtifactRoot: URL
  public let projectRoot: URL?
  public let taskProfileID: String
  public let policyContract: LearningProjectPolicyContract
  public let actionContract: LearningProjectActionContract
  public let seedCount: Int
  public let populationSize: Int
  public let generationLimit: Int?
  public let configuration: TrainingRunConfiguration

  public init(
    runID: TrainingRunID,
    source: TrainingResumeSource,
    destinationArtifactRoot: URL,
    projectRoot: URL? = nil,
    taskProfileID: String = "lift",
    policyContract: LearningProjectPolicyContract,
    actionContract: LearningProjectActionContract,
    seedCount: Int = 1,
    populationSize: Int = 1,
    generationLimit: Int? = nil,
    configuration: TrainingRunConfiguration = TrainingRunConfiguration()
  ) {
    self.runID = runID
    self.source = source
    self.destinationArtifactRoot = destinationArtifactRoot
    self.projectRoot = projectRoot
    self.taskProfileID = taskProfileID
    self.policyContract = policyContract
    self.actionContract = actionContract
    self.seedCount = max(1, seedCount)
    self.populationSize = max(1, populationSize)
    self.generationLimit = generationLimit.map { max(1, $0) }
    self.configuration = configuration
  }
}
