import Foundation

public enum TrainingDeterminismTier: String, Sendable, Codable, Equatable, CaseIterable {
    case tier0
    case tier1
    case tier2
}

public enum TrainingVariationKind: String, Sendable, Codable, Equatable, CaseIterable {
    case copy
    case gaussian

    public var contractVersion: Int {
        switch self {
        case .copy:
            1
        case .gaussian:
            2
        }
    }
}

public enum TrainingArtifactRetentionKind: String, Sendable, Codable, Equatable, CaseIterable {
    case compact
    case full
}

public struct TrainingScenarioSelection: Sendable, Codable, Equatable {
    public let suiteIDs: [Int]
    public let episodesPerSuite: Int
    public let tier: TrainingDeterminismTier
    public let cutPeriodSteps: UInt64
    public let explicitSeeds: [String]?
    public let evaluationFidelity: TrainingEvaluationFidelity
    /// Stress severity in (0, 1] applied to severity-capable suites (A1
    /// actuator swaps). nil means full severity. Severities below 1 are
    /// stamped into scenario IDs so graded evidence is never conflated with
    /// full-severity evidence.
    public let stressSeverity: Double?

    public init(
        suiteIDs: [Int] = [6],
        episodesPerSuite: Int = 1,
        tier: TrainingDeterminismTier = .tier1,
        cutPeriodSteps: UInt64 = 2,
        explicitSeeds: [String]? = nil,
        evaluationFidelity: TrainingEvaluationFidelity = .fullScenario,
        stressSeverity: Double? = nil
    ) {
        self.suiteIDs = suiteIDs.isEmpty ? [6] : suiteIDs
        self.episodesPerSuite = max(1, episodesPerSuite)
        self.tier = tier
        self.cutPeriodSteps = cutPeriodSteps
        self.explicitSeeds = explicitSeeds
        self.evaluationFidelity = evaluationFidelity
        self.stressSeverity = stressSeverity
    }
}

public struct TrainingResourcePlan: Sendable, Codable, Equatable {
    public let workerCount: Int
    public let candidateEvaluationConcurrency: Int
    public let resourceSampleSeconds: Double
    public let worldExecutionRequirement: VectorizedWorldExecutionRequirement

    public init(
        workerCount: Int = 2,
        candidateEvaluationConcurrency: Int = 24,
        resourceSampleSeconds: Double = 30,
        worldExecutionRequirement: VectorizedWorldExecutionRequirement = .acceleratorSharedWorld
    ) {
        self.workerCount = max(1, workerCount)
        self.candidateEvaluationConcurrency = max(1, candidateEvaluationConcurrency)
        self.resourceSampleSeconds = resourceSampleSeconds.isFinite ? max(0, resourceSampleSeconds) : 30
        self.worldExecutionRequirement = worldExecutionRequirement
    }
}

public struct TrainingMutationSchedule: Sendable, Codable, Equatable {
    public let rate: Double
    public let noiseScale: Double
    public let adaptiveEnabled: Bool
    public let increaseFactor: Double
    public let decayFactor: Double
    public let minimumRate: Double
    public let maximumRate: Double
    public let minimumNoiseScale: Double
    public let maximumNoiseScale: Double

    public init(
        rate: Double = 0.14,
        noiseScale: Double = 0.025,
        adaptiveEnabled: Bool = true,
        increaseFactor: Double = 1.35,
        decayFactor: Double = 0.95,
        minimumRate: Double = 0,
        maximumRate: Double = 0.8,
        minimumNoiseScale: Double = 0,
        maximumNoiseScale: Double = 0.25
    ) {
        self.rate = rate.isFinite ? max(0, rate) : 0.14
        self.noiseScale = noiseScale.isFinite ? max(0, noiseScale) : 0.025
        self.adaptiveEnabled = adaptiveEnabled
        self.increaseFactor = increaseFactor.isFinite ? max(1, increaseFactor) : 1.35
        self.decayFactor = decayFactor.isFinite ? max(0, min(1, decayFactor)) : 0.95
        self.minimumRate = minimumRate.isFinite ? max(0, minimumRate) : 0
        self.maximumRate = maximumRate.isFinite ? max(self.minimumRate, maximumRate) : 0.8
        self.minimumNoiseScale = minimumNoiseScale.isFinite ? max(0, minimumNoiseScale) : 0
        self.maximumNoiseScale = maximumNoiseScale.isFinite ? max(self.minimumNoiseScale, maximumNoiseScale) : 0.25
    }
}

public struct TrainingEvolutionSettings: Sendable, Codable, Equatable {
    public let eliteCount: Int
    public let candidateRefinement: TrainingCandidateRefinementPolicy?
    public let searchStrategy: EvolutionSearchStrategy
    public let variation: TrainingVariationKind
    public let mutation: TrainingMutationSchedule
    public let minimumIncumbentImprovement: Double
    public let minimumNoveltyScore: Double?
    /// Search-continuation budget: consecutive gate-rejected generations that
    /// may keep exploring before the run stops. nil or 0 keeps the historical
    /// stop-at-first-rejection behavior.
    public let maxConsecutiveRejectedGenerations: Int?
    /// Acceptance promotion criterion. nil means incumbentRelative (the
    /// standard capability-claim criterion). absoluteThreshold is reserved
    /// for curriculum rungs and is recorded in the run manifest.
    public let promotionCriterion: TrainingPromotionCriterion?

    public init(
        eliteCount: Int = 10,
        candidateRefinement: TrainingCandidateRefinementPolicy? = nil,
        searchStrategy: EvolutionSearchStrategy = .qualityDiversity,
        variation: TrainingVariationKind = .gaussian,
        mutation: TrainingMutationSchedule = TrainingMutationSchedule(),
        minimumIncumbentImprovement: Double = 0,
        minimumNoveltyScore: Double? = nil,
        maxConsecutiveRejectedGenerations: Int? = nil,
        promotionCriterion: TrainingPromotionCriterion? = nil
    ) {
        self.eliteCount = max(1, eliteCount)
        self.candidateRefinement = candidateRefinement
        self.searchStrategy = searchStrategy
        self.variation = variation
        self.mutation = mutation
        self.minimumIncumbentImprovement = minimumIncumbentImprovement.isFinite ? minimumIncumbentImprovement : 0
        self.minimumNoveltyScore = minimumNoveltyScore?.isFinite == true ? minimumNoveltyScore : nil
        self.maxConsecutiveRejectedGenerations = maxConsecutiveRejectedGenerations.map { max(0, $0) }
        self.promotionCriterion = promotionCriterion
    }
}

public struct TrainingConvergenceSettings: Sendable, Codable, Equatable {
    public let enabled: Bool
    public let patienceGenerations: Int
    public let minimumFitnessImprovement: Double
    public let minimumTaskPassRateImprovement: Double
    public let minimumHoldTimeRatioImprovement: Double

    public init(
        enabled: Bool = true,
        patienceGenerations: Int = 35,
        minimumFitnessImprovement: Double = 0.001,
        minimumTaskPassRateImprovement: Double = 0.001,
        minimumHoldTimeRatioImprovement: Double = 0.001
    ) {
        self.enabled = enabled
        self.patienceGenerations = max(1, patienceGenerations)
        self.minimumFitnessImprovement = minimumFitnessImprovement.isFinite ? max(0, minimumFitnessImprovement) : 0.001
        self.minimumTaskPassRateImprovement = minimumTaskPassRateImprovement.isFinite ? max(0, minimumTaskPassRateImprovement) : 0.001
        self.minimumHoldTimeRatioImprovement = minimumHoldTimeRatioImprovement.isFinite ? max(0, minimumHoldTimeRatioImprovement) : 0.001
    }
}

public struct TrainingQualityGateSettings: Sendable, Codable, Equatable {
    public let enabled: Bool
    public let minimumRewardAverage: Double?

    public init(enabled: Bool = true, minimumRewardAverage: Double? = nil) {
        self.enabled = enabled
        self.minimumRewardAverage = minimumRewardAverage?.isFinite == true ? minimumRewardAverage : nil
    }
}

public struct TrainingReinforcementSettings: Sendable, Codable, Equatable {
    public let warmupEnabled: Bool
    public let requiresTemporalActorCritic: Bool
    public let rolloutDuration: Double
    public let iterations: Int
    public let learningRate: Double
    public let maxBatches: Int?
    /// Dual-ascent step size for the Lagrangian safety-cost multiplier.
    /// nil keeps the backend default.
    public let dualLearningRate: Double?
    public let stopping: TrainingReinforcementStoppingSettings

    public init(
        warmupEnabled: Bool = true,
        requiresTemporalActorCritic: Bool = true,
        rolloutDuration: Double = 2,
        iterations: Int = 1,
        learningRate: Double = 3e-4,
        maxBatches: Int? = nil,
        dualLearningRate: Double? = nil,
        stopping: TrainingReinforcementStoppingSettings = .conservative
    ) {
        self.warmupEnabled = warmupEnabled
        self.requiresTemporalActorCritic = requiresTemporalActorCritic
        self.rolloutDuration = rolloutDuration.isFinite ? max(0.01, rolloutDuration) : 2
        self.iterations = max(1, iterations)
        self.learningRate = learningRate.isFinite ? max(0.000_001, learningRate) : 3e-4
        self.maxBatches = maxBatches.map { max(1, $0) }
        self.dualLearningRate = dualLearningRate.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        }
        self.stopping = stopping
    }
}

public struct TrainingControlSettings: Sendable, Codable, Equatable {
    public let robotManifestPath: String
    public let kp: Double
    public let kd: Double
    public let yawDamping: Double
    public let hoverScale: Double

    public init(
        robotManifestPath: String = "",
        kp: Double = 0.35,
        kd: Double = 0.08,
        yawDamping: Double = 0.04,
        hoverScale: Double = 1
    ) {
        self.robotManifestPath = robotManifestPath
        self.kp = kp.isFinite ? kp : 0.35
        self.kd = kd.isFinite ? kd : 0.08
        self.yawDamping = yawDamping.isFinite ? yawDamping : 0.04
        self.hoverScale = hoverScale.isFinite ? hoverScale : 1
    }
}

public struct TrainingArtifactPolicy: Sendable, Codable, Equatable {
    public let retention: TrainingArtifactRetentionKind
    public let allowsNonEmptyArtifactRoot: Bool
    public let requiresInitialParentPass: Bool
    public let reinforcementTrainingArtifactDirectory: URL?
    /// Resume each seed's evolution in place from its last committed generation
    /// checkpoint instead of re-seeding from generation 0.
    public let resumeInPlace: Bool
    /// Explicit generation to roll back to when resuming. nil = highest committed.
    public let resumeFromGeneration: Int?
    /// File whose presence requests a cooperative graceful stop at the next
    /// generation boundary (resumable).
    public let stopSentinelPath: String?

    public init(
        retention: TrainingArtifactRetentionKind = .compact,
        allowsNonEmptyArtifactRoot: Bool = false,
        requiresInitialParentPass: Bool = true,
        reinforcementTrainingArtifactDirectory: URL? = nil,
        resumeInPlace: Bool = false,
        resumeFromGeneration: Int? = nil,
        stopSentinelPath: String? = nil
    ) {
        self.retention = retention
        self.allowsNonEmptyArtifactRoot = allowsNonEmptyArtifactRoot
        self.requiresInitialParentPass = requiresInitialParentPass
        self.reinforcementTrainingArtifactDirectory = reinforcementTrainingArtifactDirectory
        self.resumeInPlace = resumeInPlace
        self.resumeFromGeneration = resumeFromGeneration
        self.stopSentinelPath = stopSentinelPath
    }
}

public struct TrainingRunConfiguration: Sendable, Codable, Equatable {
    public let trainingStageID: String?
    public let trainingStageDisplayName: String?
    public let trainingStageKind: AutonomousTrainingStageKind?
    public let searchScenarioSelection: TrainingScenarioSelection
    public let acceptanceScenarioSelection: TrainingScenarioSelection
    public let resources: TrainingResourcePlan
    public let evolution: TrainingEvolutionSettings
    public let convergence: TrainingConvergenceSettings
    public let qualityGate: TrainingQualityGateSettings
    public let reinforcement: TrainingReinforcementSettings
    public let control: TrainingControlSettings
    public let artifacts: TrainingArtifactPolicy
    public let autonomyDomain: AutonomousOperationDomain

    public init(
        trainingStageID: String? = nil,
        trainingStageDisplayName: String? = nil,
        trainingStageKind: AutonomousTrainingStageKind? = nil,
        searchScenarioSelection: TrainingScenarioSelection = TrainingScenarioSelection(),
        acceptanceScenarioSelection: TrainingScenarioSelection = TrainingScenarioSelection(
            suiteIDs: [6, 7, 8],
            episodesPerSuite: 3
        ),
        resources: TrainingResourcePlan = TrainingResourcePlan(),
        evolution: TrainingEvolutionSettings = TrainingEvolutionSettings(),
        convergence: TrainingConvergenceSettings = TrainingConvergenceSettings(),
        qualityGate: TrainingQualityGateSettings = TrainingQualityGateSettings(),
        reinforcement: TrainingReinforcementSettings = TrainingReinforcementSettings(),
        control: TrainingControlSettings = TrainingControlSettings(),
        artifacts: TrainingArtifactPolicy = TrainingArtifactPolicy(),
        autonomyDomain: AutonomousOperationDomain = .aerialDrone
    ) {
        self.trainingStageID = trainingStageID
        self.trainingStageDisplayName = trainingStageDisplayName
        self.trainingStageKind = trainingStageKind
        self.searchScenarioSelection = searchScenarioSelection
        self.acceptanceScenarioSelection = acceptanceScenarioSelection
        self.resources = resources
        self.evolution = evolution
        self.convergence = convergence
        self.qualityGate = qualityGate
        self.reinforcement = reinforcement
        self.control = control
        self.artifacts = artifacts
        self.autonomyDomain = autonomyDomain
    }
}
