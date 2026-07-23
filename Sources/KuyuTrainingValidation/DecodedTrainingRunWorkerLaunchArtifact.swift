import KuyuTrainingContracts

public struct DecodedTrainingRunWorkerLaunchArtifact: Sendable, Equatable {
  public let sourceVersion: TrainingRunWorkerLaunchArtifactWireVersion
  public let artifact: TrainingRunWorkerLaunchArtifact

  public init(
    sourceVersion: TrainingRunWorkerLaunchArtifactWireVersion,
    artifact: TrainingRunWorkerLaunchArtifact
  ) {
    self.sourceVersion = sourceVersion
    self.artifact = artifact
  }
}
