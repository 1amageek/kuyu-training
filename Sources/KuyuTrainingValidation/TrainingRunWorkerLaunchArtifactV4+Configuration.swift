import Foundation
import KuyuTrainingContracts

extension TrainingRunWorkerLaunchArtifactV4.Configuration {
  init(_ configuration: TrainingRunConfiguration) {
    self.init(
      trainingStageID: configuration.trainingStageID,
      trainingStageDisplayName: configuration.trainingStageDisplayName,
      trainingStageKind: configuration.trainingStageKind?.rawValue,
      searchScenarioSelection: .init(configuration.searchScenarioSelection),
      acceptanceScenarioSelection: .init(configuration.acceptanceScenarioSelection),
      resources: .init(configuration.resources),
      evolution: .init(configuration.evolution),
      convergence: .init(configuration.convergence),
      qualityGate: .init(configuration.qualityGate),
      reinforcement: .init(configuration.reinforcement),
      control: .init(configuration.control),
      artifacts: .init(configuration.artifacts),
      autonomyDomain: configuration.autonomyDomain.rawValue
    )
  }

  func domainConfiguration() throws -> TrainingRunConfiguration {
    TrainingRunConfiguration(
      trainingStageID: trainingStageID,
      trainingStageDisplayName: trainingStageDisplayName,
      trainingStageKind: try trainingStageKind.map {
        try rawValue($0, field: "configuration.trainingStageKind")
      },
      searchScenarioSelection: try searchScenarioSelection.domainSelection(
        field: "configuration.searchScenarioSelection"
      ),
      acceptanceScenarioSelection: try acceptanceScenarioSelection.domainSelection(
        field: "configuration.acceptanceScenarioSelection"
      ),
      resources: try resources.domainPlan(),
      evolution: try evolution.domainSettings(),
      convergence: try convergence.domainSettings(),
      qualityGate: try qualityGate.domainSettings(),
      reinforcement: try reinforcement.domainSettings(),
      control: try control.domainSettings(),
      artifacts: try artifacts.domainPolicy(),
      autonomyDomain: try rawValue(
        autonomyDomain,
        field: "configuration.autonomyDomain"
      )
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.ScenarioSelection {
  init(_ selection: TrainingScenarioSelection) {
    self.init(
      suiteIDs: selection.suiteIDs,
      episodesPerSuite: selection.episodesPerSuite,
      tier: selection.tier.rawValue,
      cutPeriodSteps: selection.cutPeriodSteps,
      explicitSeeds: selection.explicitSeeds,
      evaluationFidelity: .init(selection.evaluationFidelity),
      stressSeverity: selection.stressSeverity
    )
  }

  func domainSelection(field: String) throws -> TrainingScenarioSelection {
    guard !suiteIDs.isEmpty else { throw invalid(field + ".suiteIDs", "must not be empty") }
    guard suiteIDs.allSatisfy({ $0 >= 0 }) else {
      throw invalid(field + ".suiteIDs", "must not contain negative values")
    }
    guard episodesPerSuite > 0 else {
      throw invalid(field + ".episodesPerSuite", "must be greater than zero")
    }
    guard cutPeriodSteps > 0 else {
      throw invalid(field + ".cutPeriodSteps", "must be greater than zero")
    }
    if let explicitSeeds {
      guard !explicitSeeds.isEmpty else {
        throw invalid(field + ".explicitSeeds", "must be nil or non-empty")
      }
      guard explicitSeeds.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
        throw invalid(field + ".explicitSeeds", "must not contain empty values")
      }
    }
    if let stressSeverity {
      guard stressSeverity.isFinite, stressSeverity > 0, stressSeverity <= 1 else {
        throw invalid(field + ".stressSeverity", "must be in (0, 1]")
      }
    }
    return TrainingScenarioSelection(
      suiteIDs: suiteIDs,
      episodesPerSuite: episodesPerSuite,
      tier: try rawValue(tier, field: field + ".tier"),
      cutPeriodSteps: cutPeriodSteps,
      explicitSeeds: explicitSeeds,
      evaluationFidelity: try evaluationFidelity?.domainFidelity(field: field + ".evaluationFidelity")
        ?? .fullScenario,
      stressSeverity: stressSeverity
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.EvaluationFidelity {
  init(_ fidelity: TrainingEvaluationFidelity) {
    switch fidelity {
    case .fullScenario:
      self.init(kind: "fullScenario", maximumControlStepsPerEpisode: nil)
    case .screening(let maximumControlStepsPerEpisode):
      self.init(
        kind: "screening",
        maximumControlStepsPerEpisode: maximumControlStepsPerEpisode
      )
    }
  }

  func domainFidelity(field: String) throws -> TrainingEvaluationFidelity {
    switch kind {
    case "fullScenario":
      guard maximumControlStepsPerEpisode == nil else {
        throw invalid(field + ".maximumControlStepsPerEpisode", "must be absent for fullScenario")
      }
      return .fullScenario
    case "screening":
      guard let maximumControlStepsPerEpisode, maximumControlStepsPerEpisode > 0 else {
        throw invalid(field + ".maximumControlStepsPerEpisode", "must be greater than zero")
      }
      return .screening(maximumControlStepsPerEpisode: maximumControlStepsPerEpisode)
    default:
      throw invalid(field + ".kind", "unsupported value " + kind)
    }
  }
}

extension TrainingRunWorkerLaunchArtifactV4.CandidateRefinement {
  init(_ policy: TrainingCandidateRefinementPolicy) {
    self.init(
      evaluationFidelity: .init(policy.evaluationFidelity),
      candidateFraction: policy.candidateFraction,
      minimumCandidateCount: policy.minimumCandidateCount,
      retainsIncumbent: policy.retainsIncumbent
    )
  }

  func domainPolicy() throws -> TrainingCandidateRefinementPolicy {
    let policy = TrainingCandidateRefinementPolicy(
      evaluationFidelity: try evaluationFidelity.domainFidelity(
        field: "configuration.evolution.candidateRefinement.evaluationFidelity"
      ),
      candidateFraction: candidateFraction,
      minimumCandidateCount: minimumCandidateCount,
      retainsIncumbent: retainsIncumbent
    )
    do {
      try policy.validate()
    } catch {
      throw invalid(
        "configuration.evolution.candidateRefinement",
        String(describing: error)
      )
    }
    return policy
  }
}

extension TrainingRunWorkerLaunchArtifactV4.ResourcePlan {
  init(_ plan: TrainingResourcePlan) {
    self.init(
      workerCount: plan.workerCount,
      candidateEvaluationConcurrency: plan.candidateEvaluationConcurrency,
      resourceSampleSeconds: plan.resourceSampleSeconds,
      worldExecutionRequirement: plan.worldExecutionRequirement.rawValue
    )
  }

  func domainPlan() throws -> TrainingResourcePlan {
    guard workerCount > 0, candidateEvaluationConcurrency > 0 else {
      throw invalid("configuration.resources", "worker and concurrency counts must be positive")
    }
    let sampleSeconds = try finite(
      resourceSampleSeconds,
      field: "configuration.resources.resourceSampleSeconds"
    )
    guard sampleSeconds >= 0 else {
      throw invalid("configuration.resources.resourceSampleSeconds", "must not be negative")
    }
    return TrainingResourcePlan(
      workerCount: workerCount,
      candidateEvaluationConcurrency: candidateEvaluationConcurrency,
      resourceSampleSeconds: sampleSeconds,
      worldExecutionRequirement: try rawValue(
        worldExecutionRequirement,
        field: "configuration.resources.worldExecutionRequirement"
      )
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.MutationSchedule {
  init(_ schedule: TrainingMutationSchedule) {
    self.init(
      rate: schedule.rate,
      noiseScale: schedule.noiseScale,
      adaptiveEnabled: schedule.adaptiveEnabled,
      increaseFactor: schedule.increaseFactor,
      decayFactor: schedule.decayFactor,
      minimumRate: schedule.minimumRate,
      maximumRate: schedule.maximumRate,
      minimumNoiseScale: schedule.minimumNoiseScale,
      maximumNoiseScale: schedule.maximumNoiseScale
    )
  }

  func domainSchedule() throws -> TrainingMutationSchedule {
    let values = [
      ("rate", rate),
      ("noiseScale", noiseScale),
      ("increaseFactor", increaseFactor),
      ("decayFactor", decayFactor),
      ("minimumRate", minimumRate),
      ("maximumRate", maximumRate),
      ("minimumNoiseScale", minimumNoiseScale),
      ("maximumNoiseScale", maximumNoiseScale),
    ]
    for (name, value) in values {
      _ = try finite(value, field: "configuration.evolution.mutation." + name)
    }
    guard rate >= 0, noiseScale >= 0, minimumRate >= 0, minimumNoiseScale >= 0 else {
      throw invalid("configuration.evolution.mutation", "rates and scales must not be negative")
    }
    guard increaseFactor >= 1 else {
      throw invalid("configuration.evolution.mutation.increaseFactor", "must be at least one")
    }
    guard (0...1).contains(decayFactor) else {
      throw invalid("configuration.evolution.mutation.decayFactor", "must be between zero and one")
    }
    guard maximumRate >= minimumRate, maximumNoiseScale >= minimumNoiseScale else {
      throw invalid("configuration.evolution.mutation", "maximum values must not be below minimum values")
    }
    return TrainingMutationSchedule(
      rate: rate,
      noiseScale: noiseScale,
      adaptiveEnabled: adaptiveEnabled,
      increaseFactor: increaseFactor,
      decayFactor: decayFactor,
      minimumRate: minimumRate,
      maximumRate: maximumRate,
      minimumNoiseScale: minimumNoiseScale,
      maximumNoiseScale: maximumNoiseScale
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.EvolutionSettings {
  init(_ settings: TrainingEvolutionSettings) {
    self.init(
      eliteCount: settings.eliteCount,
      candidateRefinement: settings.candidateRefinement.map(
        TrainingRunWorkerLaunchArtifactV4.CandidateRefinement.init
      ),
      searchStrategy: settings.searchStrategy.rawValue,
      variation: settings.variation.rawValue,
      mutation: .init(settings.mutation),
      minimumIncumbentImprovement: settings.minimumIncumbentImprovement,
      minimumNoveltyScore: settings.minimumNoveltyScore,
      maxConsecutiveRejectedGenerations: settings.maxConsecutiveRejectedGenerations,
      promotionCriterion: settings.promotionCriterion?.rawValue
    )
  }

  func domainSettings() throws -> TrainingEvolutionSettings {
    guard eliteCount > 0 else {
      throw invalid("configuration.evolution.eliteCount", "must be greater than zero")
    }
    return TrainingEvolutionSettings(
      eliteCount: eliteCount,
      candidateRefinement: try candidateRefinement?.domainPolicy(),
      searchStrategy: try rawValue(
        searchStrategy,
        field: "configuration.evolution.searchStrategy"
      ),
      variation: try rawValue(variation, field: "configuration.evolution.variation"),
      mutation: try mutation.domainSchedule(),
      minimumIncumbentImprovement: try finite(
        minimumIncumbentImprovement,
        field: "configuration.evolution.minimumIncumbentImprovement"
      ),
      minimumNoveltyScore: try minimumNoveltyScore.map {
        try finite($0, field: "configuration.evolution.minimumNoveltyScore")
      },
      maxConsecutiveRejectedGenerations: try maxConsecutiveRejectedGenerations.map {
        guard $0 >= 0 else {
          throw invalid(
            "configuration.evolution.maxConsecutiveRejectedGenerations",
            "must be non-negative"
          )
        }
        return $0
      },
      promotionCriterion: try promotionCriterion.map {
        try rawValue($0, field: "configuration.evolution.promotionCriterion")
      }
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.ConvergenceSettings {
  init(_ settings: TrainingConvergenceSettings) {
    self.init(
      enabled: settings.enabled,
      patienceGenerations: settings.patienceGenerations,
      minimumFitnessImprovement: settings.minimumFitnessImprovement,
      minimumTaskPassRateImprovement: settings.minimumTaskPassRateImprovement,
      minimumHoldTimeRatioImprovement: settings.minimumHoldTimeRatioImprovement
    )
  }

  func domainSettings() throws -> TrainingConvergenceSettings {
    guard patienceGenerations > 0 else {
      throw invalid("configuration.convergence.patienceGenerations", "must be positive")
    }
    let fitness = try finite(
      minimumFitnessImprovement,
      field: "configuration.convergence.minimumFitnessImprovement"
    )
    let passRate = try finite(
      minimumTaskPassRateImprovement,
      field: "configuration.convergence.minimumTaskPassRateImprovement"
    )
    let holdTime = try finite(
      minimumHoldTimeRatioImprovement,
      field: "configuration.convergence.minimumHoldTimeRatioImprovement"
    )
    guard fitness >= 0, passRate >= 0, holdTime >= 0 else {
      throw invalid("configuration.convergence", "improvement thresholds must not be negative")
    }
    return TrainingConvergenceSettings(
      enabled: enabled,
      patienceGenerations: patienceGenerations,
      minimumFitnessImprovement: fitness,
      minimumTaskPassRateImprovement: passRate,
      minimumHoldTimeRatioImprovement: holdTime
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.QualityGateSettings {
  init(_ settings: TrainingQualityGateSettings) {
    self.init(enabled: settings.enabled, minimumRewardAverage: settings.minimumRewardAverage)
  }

  func domainSettings() throws -> TrainingQualityGateSettings {
    TrainingQualityGateSettings(
      enabled: enabled,
      minimumRewardAverage: try minimumRewardAverage.map {
        try finite($0, field: "configuration.qualityGate.minimumRewardAverage")
      }
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.ReinforcementSettings {
  init(_ settings: TrainingReinforcementSettings) {
    self.init(
      warmupEnabled: settings.warmupEnabled,
      requiresTemporalActorCritic: settings.requiresTemporalActorCritic,
      rolloutDuration: settings.rolloutDuration,
      iterations: settings.iterations,
      learningRate: settings.learningRate,
      maxBatches: settings.maxBatches,
      dualLearningRate: settings.dualLearningRate,
      dualInitialLambda: settings.dualInitialLambda,
      trainingSuites: settings.trainingSuites,
      stopping: .init(settings.stopping)
    )
  }

  func domainSettings() throws -> TrainingReinforcementSettings {
    let duration = try finite(
      rolloutDuration,
      field: "configuration.reinforcement.rolloutDuration"
    )
    let rate = try finite(
      learningRate,
      field: "configuration.reinforcement.learningRate"
    )
    guard duration >= 0.01, rate >= 0.000_001, iterations > 0 else {
      throw invalid("configuration.reinforcement", "duration, rate, and iterations are out of range")
    }
    if let maxBatches, maxBatches <= 0 {
      throw invalid("configuration.reinforcement.maxBatches", "must be positive")
    }
    let dualRate = try dualLearningRate.map {
      try finite($0, field: "configuration.reinforcement.dualLearningRate")
    }
    if let dualRate, dualRate <= 0 {
      throw invalid("configuration.reinforcement.dualLearningRate", "must be positive")
    }
    let dualInitial = try dualInitialLambda.map {
      try finite($0, field: "configuration.reinforcement.dualInitialLambda")
    }
    if let dualInitial, dualInitial < 0 {
      throw invalid("configuration.reinforcement.dualInitialLambda", "must be non-negative")
    }
    return TrainingReinforcementSettings(
      warmupEnabled: warmupEnabled,
      requiresTemporalActorCritic: requiresTemporalActorCritic,
      rolloutDuration: duration,
      iterations: iterations,
      learningRate: rate,
      maxBatches: maxBatches,
      dualLearningRate: dualRate,
      dualInitialLambda: dualInitial,
      trainingSuites: trainingSuites,
      stopping: try stopping?.domainSettings() ?? .conservative
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.ReinforcementStoppingSettings {
  init(_ settings: TrainingReinforcementStoppingSettings) {
    self.init(
      minimumIterationCount: settings.minimumIterationCount,
      plateauWindow: settings.plateauWindow,
      unsafeWindow: settings.unsafeWindow
    )
  }

  func domainSettings() throws -> TrainingReinforcementStoppingSettings {
    try TrainingReinforcementStoppingSettings(
      minimumIterationCount: minimumIterationCount,
      plateauWindow: plateauWindow,
      unsafeWindow: unsafeWindow
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.ControlSettings {
  init(_ settings: TrainingControlSettings) {
    self.init(
      robotManifestPath: settings.robotManifestPath,
      kp: settings.kp,
      kd: settings.kd,
      yawDamping: settings.yawDamping,
      hoverScale: settings.hoverScale
    )
  }

  func domainSettings() throws -> TrainingControlSettings {
    TrainingControlSettings(
      robotManifestPath: robotManifestPath,
      kp: try finite(kp, field: "configuration.control.kp"),
      kd: try finite(kd, field: "configuration.control.kd"),
      yawDamping: try finite(yawDamping, field: "configuration.control.yawDamping"),
      hoverScale: try finite(hoverScale, field: "configuration.control.hoverScale")
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.ArtifactPolicy {
  init(_ policy: TrainingArtifactPolicy) {
    self.init(
      retention: policy.retention.rawValue,
      allowsNonEmptyArtifactRoot: policy.allowsNonEmptyArtifactRoot,
      requiresInitialParentPass: policy.requiresInitialParentPass,
      reinforcementTrainingArtifactDirectory: policy.reinforcementTrainingArtifactDirectory?.path,
      resumeInPlace: policy.resumeInPlace,
      resumeFromGeneration: policy.resumeFromGeneration,
      stopSentinelPath: policy.stopSentinelPath
    )
  }

  func domainPolicy() throws -> TrainingArtifactPolicy {
    if let resumeFromGeneration, resumeFromGeneration < 0 {
      throw invalid("configuration.artifacts.resumeFromGeneration", "must not be negative")
    }
    return TrainingArtifactPolicy(
      retention: try rawValue(retention, field: "configuration.artifacts.retention"),
      allowsNonEmptyArtifactRoot: allowsNonEmptyArtifactRoot,
      requiresInitialParentPass: requiresInitialParentPass,
      reinforcementTrainingArtifactDirectory: try reinforcementTrainingArtifactDirectory.map {
        try absoluteDirectoryURL(
          $0,
          field: "configuration.artifacts.reinforcementTrainingArtifactDirectory"
        )
      },
      resumeInPlace: resumeInPlace,
      resumeFromGeneration: resumeFromGeneration,
      stopSentinelPath: stopSentinelPath
    )
  }
}
