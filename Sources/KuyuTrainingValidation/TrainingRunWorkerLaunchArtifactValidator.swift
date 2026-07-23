import Foundation
import KuyuTrainingContracts

public struct TrainingRunWorkerLaunchArtifactValidator: Sendable {
  public enum ValidationError: Error, Sendable, Equatable {
    case nonFiniteCreatedAt
    case emptyRunID
    case unsafeRunID(String)
    case emptyTaskProfileID
    case invalidSeedCount(Int)
    case invalidPopulationSize(Int)
    case invalidGenerationLimit(Int)
    case nonAbsoluteFileURL(field: String, path: String)
    case emptySourceBundleID
    case missingSourceBundle
    case unpinnedResumeSource(path: String)
    case missingSourceDigest(bundleID: String)
    case invalidSourceDigest(bundleID: String, digest: String)
    case invalidLearningContract(reason: String)
    case invalidEvaluationPipeline(reason: String)
    case screeningRequiresRefinement
    case fullScenarioProhibitsRefinement
    case acceptanceRequiresFullScenario
    case stopSentinelOutsideArtifactRoot(path: String, root: String)
    case nonCanonicalStopSentinel(expected: String, actual: String)
  }

  public init() {}

  public func validate(_ artifact: TrainingRunWorkerLaunchArtifact) throws {
    guard artifact.createdAt.timeIntervalSince1970.isFinite else {
      throw ValidationError.nonFiniteCreatedAt
    }
    let runID = artifact.operation.runID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !runID.isEmpty else {
      throw ValidationError.emptyRunID
    }
    guard
      runID.unicodeScalars.allSatisfy({ scalar in
        !CharacterSet.controlCharacters.contains(scalar) && scalar != "/" && scalar != "\\"
      })
    else {
      throw ValidationError.unsafeRunID(runID)
    }

    switch artifact.operation {
    case .start(let request):
      guard request.sourceBundle != nil else {
        throw ValidationError.missingSourceBundle
      }
      try validate(
        launchID: artifact.launchID,
        attemptID: artifact.attemptID,
        artifactRoot: request.artifactRoot,
        projectRoot: request.projectRoot,
        taskProfileID: request.taskProfileID,
        policyContract: request.policyContract,
        actionContract: request.actionContract,
        sourceBundle: request.sourceBundle,
        seedCount: request.seedCount,
        populationSize: request.populationSize,
        generationLimit: request.generationLimit,
        configuration: request.configuration
      )
    case .resume(let request):
      let sourceBundle: ModelBundleReference?
      switch request.source {
      case .artifactRoot(let artifactRoot):
        throw ValidationError.unpinnedResumeSource(path: artifactRoot.path)
      case .checkpoint(let checkpoint):
        sourceBundle = checkpoint
      case .continuation(let continuation):
        try validateFileURL(
          continuation.artifactRoot,
          field: "resume.source.continuation.artifactRoot"
        )
        sourceBundle = continuation.checkpoint
      }
      try validate(
        launchID: artifact.launchID,
        attemptID: artifact.attemptID,
        artifactRoot: request.destinationArtifactRoot,
        projectRoot: request.projectRoot,
        taskProfileID: request.taskProfileID,
        policyContract: request.policyContract,
        actionContract: request.actionContract,
        sourceBundle: sourceBundle,
        seedCount: request.seedCount,
        populationSize: request.populationSize,
        generationLimit: request.generationLimit,
        configuration: request.configuration
      )
    }
  }

  private func validate(
    launchID: UUID,
    attemptID: UUID,
    artifactRoot: URL,
    projectRoot: URL?,
    taskProfileID: String,
    policyContract: LearningProjectPolicyContract,
    actionContract: LearningProjectActionContract,
    sourceBundle: ModelBundleReference?,
    seedCount: Int,
    populationSize: Int,
    generationLimit: Int?,
    configuration: TrainingRunConfiguration
  ) throws {
    try validateFileURL(artifactRoot, field: "artifactRoot")
    if let projectRoot {
      try validateFileURL(projectRoot, field: "projectRoot")
    }
    guard !taskProfileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ValidationError.emptyTaskProfileID
    }
    do {
      let validator = LearningProjectContractValidator()
      try validator.validateAction(actionContract)
      try validator.validatePolicy(policyContract, action: actionContract)
    } catch {
      throw ValidationError.invalidLearningContract(reason: String(describing: error))
    }
    guard seedCount > 0 else {
      throw ValidationError.invalidSeedCount(seedCount)
    }
    guard populationSize > 0 else {
      throw ValidationError.invalidPopulationSize(populationSize)
    }
    if let generationLimit, generationLimit <= 0 {
      throw ValidationError.invalidGenerationLimit(generationLimit)
    }
    do {
      try TrainingEvaluationPipelineContract(
        searchFidelity: configuration.searchScenarioSelection.evaluationFidelity,
        refinementPolicy: configuration.evolution.candidateRefinement,
        acceptanceFidelity: configuration.acceptanceScenarioSelection.evaluationFidelity
      ).validate()
    } catch TrainingEvaluationPipelineContract.ValidationError.screeningRequiresRefinement {
      throw ValidationError.screeningRequiresRefinement
    } catch TrainingEvaluationPipelineContract.ValidationError.fullScenarioProhibitsRefinement {
      throw ValidationError.fullScenarioProhibitsRefinement
    } catch TrainingEvaluationPipelineContract.ValidationError.acceptanceRequiresFullScenario {
      throw ValidationError.acceptanceRequiresFullScenario
    } catch {
      throw ValidationError.invalidEvaluationPipeline(reason: String(describing: error))
    }
    if let sourceBundle {
      guard !sourceBundle.bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ValidationError.emptySourceBundleID
      }
      guard let digest = sourceBundle.contentHash else {
        throw ValidationError.missingSourceDigest(bundleID: sourceBundle.bundleID)
      }
      guard isSHA256Digest(digest) else {
        throw ValidationError.invalidSourceDigest(
          bundleID: sourceBundle.bundleID,
          digest: digest
        )
      }
      try validateFileURL(sourceBundle.url, field: "sourceBundle.url")
    }
    if let reinforcementRoot = configuration.artifacts.reinforcementTrainingArtifactDirectory {
      try validateFileURL(
        reinforcementRoot,
        field: "configuration.artifacts.reinforcementTrainingArtifactDirectory"
      )
    }
    if let stopSentinelPath = configuration.artifacts.stopSentinelPath {
      let stopSentinel = URL(fileURLWithPath: stopSentinelPath, isDirectory: false)
      try validateFileURL(stopSentinel, field: "configuration.artifacts.stopSentinelPath")
      let resolvedRoot = resolvedPath(artifactRoot)
      let resolvedSentinel = resolvedPath(stopSentinel)
      guard resolvedSentinel.hasPrefix(resolvedRoot + "/") else {
        throw ValidationError.stopSentinelOutsideArtifactRoot(
          path: resolvedSentinel,
          root: resolvedRoot
        )
      }
      let expectedSentinel = resolvedPath(
        TrainingRunWorkerControlPath.stopSentinelURL(
          in: artifactRoot,
          launchID: launchID,
          attemptID: attemptID
        )
      )
      guard resolvedSentinel == expectedSentinel else {
        throw ValidationError.nonCanonicalStopSentinel(
          expected: expectedSentinel,
          actual: resolvedSentinel
        )
      }
    }
  }

  private func validateFileURL(_ url: URL, field: String) throws {
    guard url.isFileURL, url.path.hasPrefix("/") else {
      throw ValidationError.nonAbsoluteFileURL(field: field, path: url.absoluteString)
    }
  }

  private func resolvedPath(_ url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
  }

  private func isSHA256Digest(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { byte in
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
      }
  }
}
