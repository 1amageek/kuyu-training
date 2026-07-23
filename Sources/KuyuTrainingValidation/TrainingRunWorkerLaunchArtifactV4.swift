import Foundation
import KuyuTrainingContracts

struct TrainingRunWorkerLaunchArtifactV4: Codable, Equatable {
  let schemaVersion: Int
  let launchID: UUID
  let attemptID: UUID
  let createdAt: Date
  let operation: Operation

  struct Operation: Codable, Equatable {
    let kind: String
    let startRequest: RunRequest?
    let resumeRequest: ResumeRequest?
  }

  struct RunRequest: Codable, Equatable {
    let runID: String
    let projectRoot: String?
    let artifactRoot: String
    let taskProfileID: String
    let policyContract: PolicyContract
    let actionContract: ActionContract
    let sourceBundle: ModelBundle?
    let seedCount: Int
    let populationSize: Int
    let generationLimit: Int?
    let configuration: Configuration
  }

  struct ResumeRequest: Codable, Equatable {
    let runID: String
    let source: ResumeSource
    let destinationArtifactRoot: String
    let projectRoot: String?
    let taskProfileID: String
    let policyContract: PolicyContract
    let actionContract: ActionContract
    let seedCount: Int
    let populationSize: Int
    let generationLimit: Int?
    let configuration: Configuration
  }

  struct ResumeSource: Codable, Equatable {
    let kind: String
    let artifactRoot: String?
    let checkpoint: ModelBundle?
    let continuation: ContinuationSource?
  }

  struct ContinuationSource: Codable, Equatable {
    let artifactRoot: String
    let checkpoint: ModelBundle
  }

  struct ModelBundle: Codable, Equatable {
    let bundleID: String
    let kind: String
    let path: String
    let provenancePath: String?
    let contentHash: String?
    let robotManifestID: String?
    let observationSchemaID: String?
    let actionSchemaID: String?
  }

  struct PolicyContract: Codable, Equatable {
    let architecture: String
    let actionEncoding: String
    let actionDistribution: ActionDistribution
    let actionDimension: Int
    let temporalWindow: TemporalWindow
    let privilegedCritic: PrivilegedCritic
    let behaviorCloning: BehaviorCloning
    let ppo: PPO
    let domainRandomization: DomainRandomization
    let actionSafety: ActionSafety
  }

  struct ActionDistribution: Codable, Equatable {
    let kind: String
    let densityContractID: String
    let baseLogStandardDeviations: [Double]
  }

  struct TemporalWindow: Codable, Equatable {
    let historyLength: Int
    let observationDimension: Int
    let previousActionDimension: Int
    let targetTrajectoryPointCount: Int
    let executionMode: String
    let paddingRule: String
    let previousActionRule: String
  }

  struct PrivilegedCritic: Codable, Equatable {
    let isEnabled: Bool
    let privilegedDimension: Int
    let parameterNames: [String]
  }

  struct BehaviorCloning: Codable, Equatable {
    let isEnabled: Bool
    let loss: String
    let initialCoefficient: Double
    let finalCoefficient: Double
  }

  struct PPO: Codable, Equatable {
    let isEnabled: Bool
    let clipEpsilon: Double
    let discount: Double
    let gaeLambda: Double
    let valueLossCoefficient: Double
    let actionSmoothnessCoefficient: Double
    let entropyRegularization: String
    let epochCount: Int
    let minibatchSize: Int
  }

  struct DomainRandomization: Codable, Equatable {
    let isEnabled: Bool
    let parameters: [DomainRandomizationParameter]
    let maximumActionLatencySteps: Int
    let maximumWindMetersPerSecond: Double
  }

  struct DomainRandomizationParameter: Codable, Equatable {
    let name: String
    let lowerMultiplier: Double
    let upperMultiplier: Double
  }

  struct ActionSafety: Codable, Equatable {
    let isEnabled: Bool
    let lowerBounds: [Double]
    let upperBounds: [Double]
    let smoothingAlpha: Double
  }

  struct ActionContract: Codable, Equatable {
    let schemaID: String
    let kind: String
    let driveCount: Int?
    let actuatorCount: Int?
    let isBounded: Bool
    let channels: [ActionChannel]
    let groups: [ActionGroup]
    let couplingRules: [ActionCouplingRule]
  }

  struct ActionChannel: Codable, Equatable {
    let index: Int
    let name: String
    let unit: String?
    let normalizedLowerBound: Double
    let normalizedUpperBound: Double
    let outputTransform: String
  }

  struct ActionGroup: Codable, Equatable {
    let groupID: String
    let displayName: String?
    let channelIndices: [Int]
    let parentGroupID: String?
    let role: String
  }

  struct ActionCouplingRule: Codable, Equatable {
    let ruleID: String
    let kind: String
    let sourceGroupID: String?
    let targetGroupID: String?
    let channelIndices: [Int]
    let coefficient: Double?
  }

  struct Configuration: Codable, Equatable {
    let trainingStageID: String?
    let trainingStageDisplayName: String?
    let trainingStageKind: String?
    let searchScenarioSelection: ScenarioSelection
    let acceptanceScenarioSelection: ScenarioSelection
    let resources: ResourcePlan
    let evolution: EvolutionSettings
    let convergence: ConvergenceSettings
    let qualityGate: QualityGateSettings
    let reinforcement: ReinforcementSettings
    let control: ControlSettings
    let artifacts: ArtifactPolicy
    let autonomyDomain: String
  }

  struct ScenarioSelection: Codable, Equatable {
    let suiteIDs: [Int]
    let episodesPerSuite: Int
    let tier: String
    let cutPeriodSteps: UInt64
    let explicitSeeds: [String]?
    let evaluationFidelity: EvaluationFidelity?
    let stressSeverity: Double?
  }

  struct EvaluationFidelity: Codable, Equatable {
    let kind: String
    let maximumControlStepsPerEpisode: Int?
  }

  struct CandidateRefinement: Codable, Equatable {
    let evaluationFidelity: EvaluationFidelity
    let candidateFraction: Double
    let minimumCandidateCount: Int
    let retainsIncumbent: Bool
  }

  struct ResourcePlan: Codable, Equatable {
    let workerCount: Int
    let candidateEvaluationConcurrency: Int
    let resourceSampleSeconds: Double
    let worldExecutionRequirement: String
  }

  struct MutationSchedule: Codable, Equatable {
    let rate: Double
    let noiseScale: Double
    let adaptiveEnabled: Bool
    let increaseFactor: Double
    let decayFactor: Double
    let minimumRate: Double
    let maximumRate: Double
    let minimumNoiseScale: Double
    let maximumNoiseScale: Double
  }

  struct EvolutionSettings: Codable, Equatable {
    let eliteCount: Int
    let candidateRefinement: CandidateRefinement?
    let searchStrategy: String
    let variation: String
    let mutation: MutationSchedule
    let minimumIncumbentImprovement: Double
    let minimumNoveltyScore: Double?
    let maxConsecutiveRejectedGenerations: Int?
    let promotionCriterion: String?
  }

  struct ConvergenceSettings: Codable, Equatable {
    let enabled: Bool
    let patienceGenerations: Int
    let minimumFitnessImprovement: Double
    let minimumTaskPassRateImprovement: Double
    let minimumHoldTimeRatioImprovement: Double
  }

  struct QualityGateSettings: Codable, Equatable {
    let enabled: Bool
    let minimumRewardAverage: Double?
  }

  struct ReinforcementSettings: Codable, Equatable {
    let warmupEnabled: Bool
    let requiresTemporalActorCritic: Bool
    let rolloutDuration: Double
    let iterations: Int
    let learningRate: Double
    let maxBatches: Int?
    let dualLearningRate: Double?
    let stopping: ReinforcementStoppingSettings?
  }

  struct ReinforcementStoppingSettings: Codable, Equatable {
    let minimumIterationCount: Int
    let plateauWindow: Int
    let unsafeWindow: Int
  }

  struct ControlSettings: Codable, Equatable {
    let robotManifestPath: String
    let kp: Double
    let kd: Double
    let yawDamping: Double
    let hoverScale: Double
  }

  struct ArtifactPolicy: Codable, Equatable {
    let retention: String
    let allowsNonEmptyArtifactRoot: Bool
    let requiresInitialParentPass: Bool
    let reinforcementTrainingArtifactDirectory: String?
    let resumeInPlace: Bool
    let resumeFromGeneration: Int?
    let stopSentinelPath: String?
  }
}
