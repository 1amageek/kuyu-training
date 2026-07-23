import Foundation

public enum TrainingRunWorkerOperation: Sendable, Equatable {
  case start(TrainingRunRequest)
  case resume(TrainingResumeRequest)

  public enum Kind: String, Sendable, Codable, Equatable {
    case start
    case resume
  }

  public var kind: Kind {
    switch self {
    case .start:
      .start
    case .resume:
      .resume
    }
  }

  public var runID: TrainingRunID {
    switch self {
    case .start(let request):
      request.runID
    case .resume(let request):
      request.runID
    }
  }

  public var artifactRoot: URL {
    switch self {
    case .start(let request):
      request.artifactRoot
    case .resume(let request):
      request.destinationArtifactRoot
    }
  }

  public var configuration: TrainingRunConfiguration {
    switch self {
    case .start(let request):
      request.configuration
    case .resume(let request):
      request.configuration
    }
  }

}
