import Foundation
import KuyuTrainingContracts

extension TrainingRunWorkerLaunchArtifactV4 {
  init(_ artifact: TrainingRunWorkerLaunchArtifact) {
    self.init(
      schemaVersion: TrainingRunWorkerLaunchArtifactWireVersion.current.rawValue,
      launchID: artifact.launchID,
      attemptID: artifact.attemptID,
      createdAt: artifact.createdAt,
      operation: Operation(artifact.operation)
    )
  }

  func domainArtifact() throws -> TrainingRunWorkerLaunchArtifact {
    guard schemaVersion == TrainingRunWorkerLaunchArtifactWireVersion.v4.rawValue else {
      throw TrainingRunWorkerLaunchArtifactCodec.CodecError.unsupportedSchemaVersion(schemaVersion)
    }
    return TrainingRunWorkerLaunchArtifact(
      launchID: launchID,
      attemptID: attemptID,
      createdAt: createdAt,
      operation: try operation.domainOperation()
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.Operation {
  init(_ operation: TrainingRunWorkerOperation) {
    switch operation {
    case .start(let request):
      self.init(kind: "start", startRequest: .init(request), resumeRequest: nil)
    case .resume(let request):
      self.init(kind: "resume", startRequest: nil, resumeRequest: .init(request))
    }
  }

  func domainOperation() throws -> TrainingRunWorkerOperation {
    switch kind {
    case "start":
      guard let startRequest, resumeRequest == nil else {
        throw invalid("operation", "start requires only startRequest")
      }
      return .start(try startRequest.domainRequest())
    case "resume":
      guard let resumeRequest, startRequest == nil else {
        throw invalid("operation", "resume requires only resumeRequest")
      }
      return .resume(try resumeRequest.domainRequest())
    default:
      throw invalid("operation.kind", "unsupported value \(kind)")
    }
  }
}

extension TrainingRunWorkerLaunchArtifactV4.RunRequest {
  init(_ request: TrainingRunRequest) {
    self.init(
      runID: request.runID.rawValue,
      projectRoot: request.projectRoot?.path,
      artifactRoot: request.artifactRoot.path,
      taskProfileID: request.taskProfileID,
      policyContract: .init(request.policyContract),
      actionContract: .init(request.actionContract),
      sourceBundle: request.sourceBundle.map(TrainingRunWorkerLaunchArtifactV4.ModelBundle.init),
      seedCount: request.seedCount,
      populationSize: request.populationSize,
      generationLimit: request.generationLimit,
      configuration: .init(request.configuration)
    )
  }

  func domainRequest() throws -> TrainingRunRequest {
    try validateRunBudget(
      seedCount: seedCount,
      populationSize: populationSize,
      generationLimit: generationLimit
    )
    return TrainingRunRequest(
      runID: TrainingRunID(runID),
      projectRoot: try projectRoot.map { try absoluteDirectoryURL($0, field: "projectRoot") },
      artifactRoot: try absoluteDirectoryURL(artifactRoot, field: "artifactRoot"),
      taskProfileID: taskProfileID,
      policyContract: try policyContract.domainContract(),
      actionContract: try actionContract.domainContract(),
      sourceBundle: try sourceBundle?.domainReference(),
      seedCount: seedCount,
      populationSize: populationSize,
      generationLimit: generationLimit,
      configuration: try configuration.domainConfiguration()
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.ResumeRequest {
  init(_ request: TrainingResumeRequest) {
    self.init(
      runID: request.runID.rawValue,
      source: .init(request.source),
      destinationArtifactRoot: request.destinationArtifactRoot.path,
      projectRoot: request.projectRoot?.path,
      taskProfileID: request.taskProfileID,
      policyContract: .init(request.policyContract),
      actionContract: .init(request.actionContract),
      seedCount: request.seedCount,
      populationSize: request.populationSize,
      generationLimit: request.generationLimit,
      configuration: .init(request.configuration)
    )
  }

  func domainRequest() throws -> TrainingResumeRequest {
    try validateRunBudget(
      seedCount: seedCount,
      populationSize: populationSize,
      generationLimit: generationLimit
    )
    return TrainingResumeRequest(
      runID: TrainingRunID(runID),
      source: try source.domainSource(),
      destinationArtifactRoot: try absoluteDirectoryURL(
        destinationArtifactRoot,
        field: "destinationArtifactRoot"
      ),
      projectRoot: try projectRoot.map { try absoluteDirectoryURL($0, field: "projectRoot") },
      taskProfileID: taskProfileID,
      policyContract: try policyContract.domainContract(),
      actionContract: try actionContract.domainContract(),
      seedCount: seedCount,
      populationSize: populationSize,
      generationLimit: generationLimit,
      configuration: try configuration.domainConfiguration()
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.ResumeSource {
  init(_ source: TrainingResumeSource) {
    switch source {
    case .artifactRoot(let root):
      self.init(kind: "artifactRoot", artifactRoot: root.path, checkpoint: nil, continuation: nil)
    case .checkpoint(let checkpoint):
      self.init(kind: "checkpoint", artifactRoot: nil, checkpoint: .init(checkpoint), continuation: nil)
    case .continuation(let continuation):
      self.init(
        kind: "continuation",
        artifactRoot: nil,
        checkpoint: nil,
        continuation: .init(continuation)
      )
    }
  }

  func domainSource() throws -> TrainingResumeSource {
    switch kind {
    case "artifactRoot":
      guard let artifactRoot, checkpoint == nil, continuation == nil else {
        throw invalid("resume.source", "artifactRoot payload is inconsistent")
      }
      return .artifactRoot(
        try absoluteDirectoryURL(artifactRoot, field: "resume.source.artifactRoot")
      )
    case "checkpoint":
      guard let checkpoint, artifactRoot == nil, continuation == nil else {
        throw invalid("resume.source", "checkpoint payload is inconsistent")
      }
      return .checkpoint(try checkpoint.domainReference())
    case "continuation":
      guard let continuation, artifactRoot == nil, checkpoint == nil else {
        throw invalid("resume.source", "continuation payload is inconsistent")
      }
      return .continuation(try continuation.domainSource())
    default:
      throw invalid("resume.source.kind", "unsupported value \(kind)")
    }
  }
}

extension TrainingRunWorkerLaunchArtifactV4.ContinuationSource {
  init(_ source: TrainingContinuationResumeSource) {
    self.init(artifactRoot: source.artifactRoot.path, checkpoint: .init(source.checkpoint))
  }

  func domainSource() throws -> TrainingContinuationResumeSource {
    TrainingContinuationResumeSource(
      artifactRoot: try absoluteDirectoryURL(
        artifactRoot,
        field: "resume.source.continuation.artifactRoot"
      ),
      checkpoint: try checkpoint.domainReference()
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.ModelBundle {
  init(_ reference: ModelBundleReference) {
    self.init(
      bundleID: reference.bundleID,
      kind: reference.kind.rawValue,
      path: reference.url.path,
      provenancePath: reference.provenanceURL?.path,
      contentHash: reference.contentHash,
      robotManifestID: reference.robotManifestID,
      observationSchemaID: reference.observationSchemaID,
      actionSchemaID: reference.actionSchemaID
    )
  }

  func domainReference() throws -> ModelBundleReference {
    ModelBundleReference(
      bundleID: bundleID,
      kind: try rawValue(kind, field: "modelBundle.kind"),
      url: try absoluteDirectoryURL(path, field: "modelBundle.path"),
      provenanceURL: try provenancePath.map {
        try absoluteDirectoryURL($0, field: "modelBundle.provenancePath")
      },
      contentHash: contentHash,
      robotManifestID: robotManifestID,
      observationSchemaID: observationSchemaID,
      actionSchemaID: actionSchemaID
    )
  }
}

func validateRunBudget(
  seedCount: Int,
  populationSize: Int,
  generationLimit: Int?
) throws {
  guard seedCount > 0 else { throw invalid("seedCount", "must be greater than zero") }
  guard populationSize > 0 else { throw invalid("populationSize", "must be greater than zero") }
  if let generationLimit, generationLimit <= 0 {
    throw invalid("generationLimit", "must be greater than zero")
  }
}

func absoluteDirectoryURL(_ path: String, field: String) throws -> URL {
  guard path.hasPrefix("/") else { throw invalid(field, "must be an absolute path") }
  return URL(fileURLWithPath: path, isDirectory: true)
}

func rawValue<Value: RawRepresentable>(
  _ value: String,
  field: String
) throws -> Value where Value.RawValue == String {
  guard let result = Value(rawValue: value) else {
    throw invalid(field, "unsupported value \(value)")
  }
  return result
}

func finite(_ value: Double, field: String) throws -> Double {
  guard value.isFinite else { throw invalid(field, "must be finite") }
  return value
}

func invalid(
  _ field: String,
  _ reason: String
) -> TrainingRunWorkerLaunchArtifactCodec.CodecError {
  .invalidValue(field: field, reason: reason)
}
