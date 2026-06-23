import Foundation

public struct LearningProjectCurriculum: Codable, Sendable, Equatable {
    public let suiteIDs: [Int]
    public let seedCount: Int
    public let episodesPerSuite: Int
    public let populationSize: Int
    public let generationLimit: Int
    public let convergenceGoal: LearningProjectConvergenceGoal
    public let eliteCount: Int
    public let maxStepCount: Int?
    public let trainingStages: [LearningProjectTrainingStage]

    private enum CodingKeys: String, CodingKey {
        case suiteIDs
        case seedCount
        case episodesPerSuite
        case populationSize
        case generationLimit
        case convergenceGoal
        case eliteCount
        case maxStepCount
        case trainingStages
    }

    public init(
        suiteIDs: [Int],
        seedCount: Int,
        episodesPerSuite: Int,
        populationSize: Int,
        generationLimit: Int,
        convergenceGoal: LearningProjectConvergenceGoal? = nil,
        eliteCount: Int,
        maxStepCount: Int?,
        trainingStages: [LearningProjectTrainingStage]? = nil
    ) {
        self.suiteIDs = suiteIDs
        self.seedCount = seedCount
        self.episodesPerSuite = episodesPerSuite
        self.populationSize = populationSize
        self.generationLimit = generationLimit
        self.convergenceGoal = convergenceGoal ?? LearningProjectConvergenceGoal(
            patienceGenerations: min(20, max(1, generationLimit)),
            maxGenerationBudget: generationLimit
        )
        self.eliteCount = eliteCount
        self.maxStepCount = maxStepCount
        self.trainingStages = trainingStages ?? [
            LearningProjectTrainingStage(
                stageID: "imitation-bootstrap",
                kind: .imitation,
                displayName: "Imitation Bootstrap",
                task: "default",
                taskProfileID: nil,
                suiteIDs: suiteIDs,
                seedCount: seedCount,
                episodesPerSuite: episodesPerSuite,
                generationLimit: min(100, generationLimit),
                convergenceGoal: LearningProjectConvergenceGoal(
                    kind: .convergence,
                    patienceGenerations: min(20, max(1, min(100, generationLimit))),
                    maxGenerationBudget: min(100, generationLimit)
                ),
                executionMode: .sequential,
                dependsOnStageIDs: [],
                capabilities: [.sensorIngestion, .stateEstimation]
            ),
            LearningProjectTrainingStage(
                stageID: "closed-loop-reinforcement",
                kind: .reinforcement,
                displayName: "Closed-loop Reinforcement",
                task: "default",
                taskProfileID: nil,
                suiteIDs: suiteIDs,
                seedCount: seedCount,
                episodesPerSuite: episodesPerSuite,
                generationLimit: generationLimit,
                convergenceGoal: self.convergenceGoal,
                executionMode: .sequential,
                dependsOnStageIDs: ["imitation-bootstrap"],
                capabilities: [.dynamicsStabilization, .trajectoryTracking, .safeStop]
            ),
            LearningProjectTrainingStage(
                stageID: "evolution-search",
                kind: .evolution,
                displayName: "Population Evolution Search",
                task: "default",
                taskProfileID: nil,
                suiteIDs: suiteIDs,
                seedCount: seedCount,
                episodesPerSuite: episodesPerSuite,
                generationLimit: generationLimit,
                convergenceGoal: self.convergenceGoal,
                executionMode: .parallel,
                dependsOnStageIDs: ["closed-loop-reinforcement"],
                capabilities: [.trajectoryTracking, .recoveryBehavior, .safeStop]
            ),
            LearningProjectTrainingStage(
                stageID: "full-regression",
                kind: .regression,
                displayName: "Full Regression Gate",
                task: "default",
                taskProfileID: nil,
                suiteIDs: suiteIDs,
                seedCount: seedCount,
                episodesPerSuite: episodesPerSuite,
                generationLimit: 1,
                convergenceGoal: LearningProjectConvergenceGoal(
                    kind: .validationGate,
                    patienceGenerations: 1,
                    maxGenerationBudget: 1
                ),
                executionMode: .sequential,
                dependsOnStageIDs: ["evolution-search"],
                capabilities: [.dynamicsStabilization, .trajectoryTracking, .recoveryBehavior, .safeStop]
            )
        ]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let suiteIDs = try container.decode([Int].self, forKey: .suiteIDs)
        let seedCount = try container.decode(Int.self, forKey: .seedCount)
        let episodesPerSuite = try container.decode(Int.self, forKey: .episodesPerSuite)
        let populationSize = try container.decode(Int.self, forKey: .populationSize)
        let generationLimit = try container.decode(Int.self, forKey: .generationLimit)
        let convergenceGoal = try container.decodeIfPresent(
            LearningProjectConvergenceGoal.self,
            forKey: .convergenceGoal
        )
        let eliteCount = try container.decode(Int.self, forKey: .eliteCount)
        let maxStepCount = try container.decodeIfPresent(Int.self, forKey: .maxStepCount)
        let trainingStages = try container.decodeIfPresent(
            [LearningProjectTrainingStage].self,
            forKey: .trainingStages
        )

        self.init(
            suiteIDs: suiteIDs,
            seedCount: seedCount,
            episodesPerSuite: episodesPerSuite,
            populationSize: populationSize,
            generationLimit: generationLimit,
            convergenceGoal: convergenceGoal,
            eliteCount: eliteCount,
            maxStepCount: maxStepCount,
            trainingStages: trainingStages
        )
    }
}
