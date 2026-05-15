import Foundation

public enum EvolutionRunTerminalState: String, Sendable, Codable, Equatable {
    case running
    case completed
    case failed
    case rejected
    case cancelled
}

public enum EvolutionSearchStrategy: String, Sendable, Codable, Equatable {
    case genetic
    case antitheticEvolutionStrategy
    case qualityDiversity
}

public enum EvolutionBootstrapSource: String, Sendable, Codable, Equatable {
    case checkpoint
    case teacher
    case demonstration
    case none
}

public enum EvolutionWorldModelUsage: String, Sendable, Codable, Equatable {
    case disabled
    case evaluationAssist
    case imaginationAssist
}

public struct EvolutionRunManifest: Sendable, Codable, Equatable {
    public let runID: String
    public let taskID: String
    public let descriptorID: String?
    public let descriptorHash: String?
    public let configHash: String
    public let policyID: String
    public let populationSize: Int
    public let generationCount: Int
    public let eliteCount: Int
    public let workerCount: Int
    public let candidateEvaluationConcurrency: Int
    public let searchStrategy: EvolutionSearchStrategy
    public let bootstrapSource: EvolutionBootstrapSource
    public let worldModelUsage: EvolutionWorldModelUsage
    public let antitheticSampling: Bool
    public let commonRandomSeed: UInt64
    public let mutationRate: Double
    public let mutationNoiseScale: Double
    public let parentCheckpointID: String?
    public let startedAt: Date
    public let completedAt: Date?
    public let terminalState: EvolutionRunTerminalState
    public let failureReason: String?

    public init(
        runID: String,
        taskID: String,
        descriptorID: String? = nil,
        descriptorHash: String? = nil,
        configHash: String,
        policyID: String,
        populationSize: Int,
        generationCount: Int,
        eliteCount: Int,
        workerCount: Int,
        candidateEvaluationConcurrency: Int = 1,
        searchStrategy: EvolutionSearchStrategy = .genetic,
        bootstrapSource: EvolutionBootstrapSource = .checkpoint,
        worldModelUsage: EvolutionWorldModelUsage = .disabled,
        antitheticSampling: Bool = false,
        commonRandomSeed: UInt64 = 0,
        mutationRate: Double = 0,
        mutationNoiseScale: Double = 0,
        parentCheckpointID: String? = nil,
        startedAt: Date,
        completedAt: Date? = nil,
        terminalState: EvolutionRunTerminalState,
        failureReason: String? = nil
    ) {
        self.runID = runID
        self.taskID = taskID
        self.descriptorID = descriptorID
        self.descriptorHash = descriptorHash
        self.configHash = configHash
        self.policyID = policyID
        self.populationSize = max(1, populationSize)
        self.generationCount = max(1, generationCount)
        self.eliteCount = max(1, eliteCount)
        self.workerCount = max(1, workerCount)
        self.candidateEvaluationConcurrency = max(1, candidateEvaluationConcurrency)
        self.searchStrategy = searchStrategy
        self.bootstrapSource = bootstrapSource
        self.worldModelUsage = worldModelUsage
        self.antitheticSampling = antitheticSampling
        self.commonRandomSeed = commonRandomSeed
        self.mutationRate = mutationRate
        self.mutationNoiseScale = mutationNoiseScale
        self.parentCheckpointID = parentCheckpointID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.terminalState = terminalState
        self.failureReason = failureReason
    }

    public func completed(
        at completedAt: Date,
        terminalState: EvolutionRunTerminalState,
        failureReason: String? = nil
    ) -> EvolutionRunManifest {
        EvolutionRunManifest(
            runID: runID,
            taskID: taskID,
            descriptorID: descriptorID,
            descriptorHash: descriptorHash,
            configHash: configHash,
            policyID: policyID,
            populationSize: populationSize,
            generationCount: generationCount,
            eliteCount: eliteCount,
            workerCount: workerCount,
            candidateEvaluationConcurrency: candidateEvaluationConcurrency,
            searchStrategy: searchStrategy,
            bootstrapSource: bootstrapSource,
            worldModelUsage: worldModelUsage,
            antitheticSampling: antitheticSampling,
            commonRandomSeed: commonRandomSeed,
            mutationRate: mutationRate,
            mutationNoiseScale: mutationNoiseScale,
            parentCheckpointID: parentCheckpointID,
            startedAt: startedAt,
            completedAt: completedAt,
            terminalState: terminalState,
            failureReason: failureReason
        )
    }
}

public struct EvolutionRunConfig: Sendable, Codable, Equatable {
    public let runID: String
    public let taskID: String
    public let descriptorID: String?
    public let descriptorHash: String?
    public let configHash: String
    public let policyID: String
    public let populationSize: Int
    public let generationCount: Int
    public let eliteCount: Int
    public let workerCount: Int
    public let candidateEvaluationConcurrency: Int
    public let searchStrategy: EvolutionSearchStrategy
    public let bootstrapSource: EvolutionBootstrapSource
    public let worldModelUsage: EvolutionWorldModelUsage
    public let antitheticSampling: Bool
    public let commonRandomSeed: UInt64
    public let mutationRate: Double
    public let mutationNoiseScale: Double
    public let adaptiveMutation: EvolutionAdaptiveMutationConfig
    public let earlyStopping: EvolutionEarlyStoppingConfig
    public let worldExecutionRequirement: VectorizedWorldExecutionRequirement
    public let parentCheckpointID: String?
    public let parentCheckpointURL: URL?

    public init(
        runID: String = UUID().uuidString,
        taskID: String,
        descriptorID: String? = nil,
        descriptorHash: String? = nil,
        configHash: String,
        policyID: String,
        populationSize: Int,
        generationCount: Int,
        eliteCount: Int,
        workerCount: Int = 1,
        candidateEvaluationConcurrency: Int = 1,
        searchStrategy: EvolutionSearchStrategy = .genetic,
        bootstrapSource: EvolutionBootstrapSource = .checkpoint,
        worldModelUsage: EvolutionWorldModelUsage = .disabled,
        antitheticSampling: Bool = false,
        commonRandomSeed: UInt64 = 1,
        mutationRate: Double,
        mutationNoiseScale: Double = 0.01,
        adaptiveMutation: EvolutionAdaptiveMutationConfig = EvolutionAdaptiveMutationConfig(),
        earlyStopping: EvolutionEarlyStoppingConfig = EvolutionEarlyStoppingConfig(),
        worldExecutionRequirement: VectorizedWorldExecutionRequirement = .acceleratorSharedWorld,
        parentCheckpointID: String? = nil,
        parentCheckpointURL: URL? = nil
    ) {
        self.runID = runID
        self.taskID = taskID
        self.descriptorID = descriptorID
        self.descriptorHash = descriptorHash
        self.configHash = configHash
        self.policyID = policyID
        self.populationSize = max(1, populationSize)
        self.generationCount = max(1, generationCount)
        self.eliteCount = max(1, min(eliteCount, populationSize))
        self.workerCount = max(1, workerCount)
        self.candidateEvaluationConcurrency = max(1, min(candidateEvaluationConcurrency, populationSize))
        self.searchStrategy = searchStrategy
        self.bootstrapSource = bootstrapSource
        self.worldModelUsage = worldModelUsage
        self.antitheticSampling = antitheticSampling || searchStrategy == .antitheticEvolutionStrategy
        self.commonRandomSeed = commonRandomSeed == 0 ? 1 : commonRandomSeed
        self.mutationRate = mutationRate
        self.mutationNoiseScale = max(0, mutationNoiseScale)
        self.adaptiveMutation = adaptiveMutation
        self.earlyStopping = earlyStopping
        self.worldExecutionRequirement = worldExecutionRequirement
        self.parentCheckpointID = parentCheckpointID
        self.parentCheckpointURL = parentCheckpointURL
    }
}

public struct EvolutionEarlyStoppingConfig: Sendable, Codable, Equatable {
    public let enabled: Bool
    public let patienceGenerations: Int
    public let minimumFitnessImprovement: Double
    public let minimumTaskPassRateImprovement: Double
    public let minimumHoldTimeRatioImprovement: Double

    public init(
        enabled: Bool = true,
        patienceGenerations: Int = 20,
        minimumFitnessImprovement: Double = 0.001,
        minimumTaskPassRateImprovement: Double = 0.001,
        minimumHoldTimeRatioImprovement: Double = 0.001
    ) {
        self.enabled = enabled
        self.patienceGenerations = max(1, patienceGenerations)
        self.minimumFitnessImprovement = max(0, minimumFitnessImprovement)
        self.minimumTaskPassRateImprovement = max(0, minimumTaskPassRateImprovement)
        self.minimumHoldTimeRatioImprovement = max(0, minimumHoldTimeRatioImprovement)
    }
}

public struct EvolutionAdaptiveMutationConfig: Sendable, Codable, Equatable {
    public let enabled: Bool
    public let increaseFactor: Double
    public let decayFactor: Double
    public let minimumMutationRate: Double
    public let maximumMutationRate: Double
    public let minimumNoiseScale: Double
    public let maximumNoiseScale: Double

    public init(
        enabled: Bool = false,
        increaseFactor: Double = 1.25,
        decayFactor: Double = 0.9,
        minimumMutationRate: Double = 0,
        maximumMutationRate: Double = 0.5,
        minimumNoiseScale: Double = 0,
        maximumNoiseScale: Double = 0.1
    ) {
        self.enabled = enabled
        self.increaseFactor = max(1, increaseFactor)
        self.decayFactor = min(1, max(0, decayFactor))
        self.minimumMutationRate = max(0, minimumMutationRate)
        self.maximumMutationRate = max(self.minimumMutationRate, maximumMutationRate)
        self.minimumNoiseScale = max(0, minimumNoiseScale)
        self.maximumNoiseScale = max(self.minimumNoiseScale, maximumNoiseScale)
    }
}

public struct GenomeCandidate: Sendable, Codable, Equatable {
    public let runID: String
    public let generationIndex: Int
    public let candidateID: String
    public let genomeID: String
    public let parentCandidateIDs: [String]
    public let checkpointID: String?
    public let checkpointURL: URL?
    public let mutationRate: Double?
    public let mutationNoiseScale: Double?
    public let commonRandomSeed: UInt64?
    public let antitheticPairID: String?
    public let antitheticSign: Int?
    public let mutationSummary: String?
    public let isIncumbent: Bool?

    public init(
        runID: String,
        generationIndex: Int,
        candidateID: String,
        genomeID: String,
        parentCandidateIDs: [String] = [],
        checkpointID: String? = nil,
        checkpointURL: URL? = nil,
        mutationRate: Double? = nil,
        mutationNoiseScale: Double? = nil,
        commonRandomSeed: UInt64? = nil,
        antitheticPairID: String? = nil,
        antitheticSign: Int? = nil,
        mutationSummary: String? = nil,
        isIncumbent: Bool = false
    ) {
        self.runID = runID
        self.generationIndex = max(0, generationIndex)
        self.candidateID = candidateID
        self.genomeID = genomeID
        self.parentCandidateIDs = parentCandidateIDs
        self.checkpointID = checkpointID
        self.checkpointURL = checkpointURL
        self.mutationRate = mutationRate
        self.mutationNoiseScale = mutationNoiseScale
        self.commonRandomSeed = commonRandomSeed
        self.antitheticPairID = antitheticPairID
        self.antitheticSign = antitheticSign
        self.mutationSummary = mutationSummary
        self.isIncumbent = isIncumbent
    }
}

public struct EvolutionPopulation: Sendable, Codable, Equatable {
    public let runID: String
    public let generationIndex: Int
    public let candidates: [GenomeCandidate]

    public init(runID: String, generationIndex: Int, candidates: [GenomeCandidate]) {
        self.runID = runID
        self.generationIndex = max(0, generationIndex)
        self.candidates = candidates
    }
}

public struct FitnessSummary: Sendable, Codable, Equatable {
    public let runID: String
    public let generationIndex: Int
    public let candidateID: String
    public let taskID: String
    public let scalarFitness: Double
    public let rewardAverage: Double
    public let taskPassRate: Double
    public let safetyViolationRate: Double
    public let holdTimeRatio: Double?
    public let altitudeErrorRatio: Double?
    public let energyPenalty: Double?
    public let noveltyScore: Double?
    public let teacherDelta: Double?
    public let workerThroughput: Double?
    public let behaviorDescriptor: [String: Double]
    public let failureReasons: [String]

    public init(
        runID: String,
        generationIndex: Int,
        candidateID: String,
        taskID: String,
        scalarFitness: Double,
        rewardAverage: Double,
        taskPassRate: Double,
        safetyViolationRate: Double,
        holdTimeRatio: Double? = nil,
        altitudeErrorRatio: Double? = nil,
        energyPenalty: Double? = nil,
        noveltyScore: Double? = nil,
        teacherDelta: Double? = nil,
        workerThroughput: Double? = nil,
        behaviorDescriptor: [String: Double] = [:],
        failureReasons: [String] = []
    ) {
        self.runID = runID
        self.generationIndex = max(0, generationIndex)
        self.candidateID = candidateID
        self.taskID = taskID
        self.scalarFitness = scalarFitness
        self.rewardAverage = rewardAverage
        self.taskPassRate = taskPassRate
        self.safetyViolationRate = safetyViolationRate
        self.holdTimeRatio = holdTimeRatio
        self.altitudeErrorRatio = altitudeErrorRatio
        self.energyPenalty = energyPenalty
        self.noveltyScore = noveltyScore
        self.teacherDelta = teacherDelta
        self.workerThroughput = workerThroughput
        self.behaviorDescriptor = behaviorDescriptor
        self.failureReasons = failureReasons
    }
}

public struct PopulationGenerationRecord: Sendable, Codable, Equatable {
    public let runID: String
    public let generationIndex: Int
    public let candidateCount: Int
    public let evaluatedCandidateCount: Int
    public let eliteCandidateIDs: [String]
    public let bestCandidateID: String?
    public let bestFitness: Double?
    public let incumbentCandidateID: String?
    public let incumbentFitness: Double?
    public let bestVsIncumbentDelta: Double?
    public let minimumImprovementOverIncumbent: Double?
    public let incumbentImproved: Bool
    public let qualityDiversityCellCount: Int
    public let mutationRate: Double
    public let mutationNoiseScale: Double
    public let accepted: Bool
    public let rejectionReasons: [String]
    public let createdAt: Date

    public init(
        runID: String,
        generationIndex: Int,
        candidateCount: Int,
        evaluatedCandidateCount: Int,
        eliteCandidateIDs: [String],
        bestCandidateID: String?,
        bestFitness: Double?,
        incumbentCandidateID: String? = nil,
        incumbentFitness: Double? = nil,
        bestVsIncumbentDelta: Double? = nil,
        minimumImprovementOverIncumbent: Double? = nil,
        incumbentImproved: Bool? = nil,
        qualityDiversityCellCount: Int = 0,
        mutationRate: Double = 0,
        mutationNoiseScale: Double = 0,
        accepted: Bool,
        rejectionReasons: [String],
        createdAt: Date = Date()
    ) {
        self.runID = runID
        self.generationIndex = max(0, generationIndex)
        self.candidateCount = max(0, candidateCount)
        self.evaluatedCandidateCount = max(0, evaluatedCandidateCount)
        self.eliteCandidateIDs = eliteCandidateIDs
        self.bestCandidateID = bestCandidateID
        self.bestFitness = bestFitness
        self.incumbentCandidateID = incumbentCandidateID
        self.incumbentFitness = incumbentFitness
        self.bestVsIncumbentDelta = bestVsIncumbentDelta
        self.minimumImprovementOverIncumbent = minimumImprovementOverIncumbent
        self.incumbentImproved = incumbentImproved ?? bestVsIncumbentDelta.map {
            $0 > (minimumImprovementOverIncumbent ?? 0)
        } ?? false
        self.qualityDiversityCellCount = max(0, qualityDiversityCellCount)
        self.mutationRate = max(0, mutationRate)
        self.mutationNoiseScale = max(0, mutationNoiseScale)
        self.accepted = accepted
        self.rejectionReasons = rejectionReasons
        self.createdAt = createdAt
    }
}
