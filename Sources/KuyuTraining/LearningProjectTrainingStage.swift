public struct LearningProjectTrainingStage: Codable, Sendable, Equatable {
    public let stageID: String
    public let kind: AutonomousTrainingStageKind
    public let displayName: String
    public let task: String
    public let taskProfileID: String?
    public let suiteIDs: [Int]
    public let seedCount: Int
    public let episodesPerSuite: Int
    public let generationLimit: Int
    public let convergenceGoal: LearningProjectConvergenceGoal
    public let executionMode: LearningProjectTrainingExecutionMode
    public let dependsOnStageIDs: [String]
    public let capabilities: [AutonomousCapability]

    private enum CodingKeys: String, CodingKey {
        case stageID
        case kind
        case displayName
        case task
        case taskProfileID
        case suiteIDs
        case seedCount
        case episodesPerSuite
        case generationLimit
        case convergenceGoal
        case executionMode
        case dependsOnStageIDs
        case capabilities
    }

    public init(
        stageID: String,
        kind: AutonomousTrainingStageKind,
        displayName: String,
        task: String,
        taskProfileID: String?,
        suiteIDs: [Int],
        seedCount: Int,
        episodesPerSuite: Int,
        generationLimit: Int,
        convergenceGoal: LearningProjectConvergenceGoal? = nil,
        executionMode: LearningProjectTrainingExecutionMode,
        dependsOnStageIDs: [String],
        capabilities: [AutonomousCapability]
    ) {
        self.stageID = stageID
        self.kind = kind
        self.displayName = displayName
        self.task = task
        self.taskProfileID = taskProfileID
        self.suiteIDs = suiteIDs
        self.seedCount = seedCount
        self.episodesPerSuite = episodesPerSuite
        self.generationLimit = generationLimit
        self.convergenceGoal = convergenceGoal ?? LearningProjectConvergenceGoal(
            patienceGenerations: min(20, max(1, generationLimit)),
            maxGenerationBudget: generationLimit
        )
        self.executionMode = executionMode
        self.dependsOnStageIDs = dependsOnStageIDs
        self.capabilities = capabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stageID = try container.decode(String.self, forKey: .stageID)
        let kind = try container.decode(AutonomousTrainingStageKind.self, forKey: .kind)
        let displayName = try container.decode(String.self, forKey: .displayName)
        let task = try container.decode(String.self, forKey: .task)
        let taskProfileID = try container.decodeIfPresent(String.self, forKey: .taskProfileID)
        let suiteIDs = try container.decode([Int].self, forKey: .suiteIDs)
        let seedCount = try container.decode(Int.self, forKey: .seedCount)
        let episodesPerSuite = try container.decode(Int.self, forKey: .episodesPerSuite)
        let generationLimit = try container.decode(Int.self, forKey: .generationLimit)
        let convergenceGoal = try container.decodeIfPresent(
            LearningProjectConvergenceGoal.self,
            forKey: .convergenceGoal
        )
        let executionMode = try container.decode(LearningProjectTrainingExecutionMode.self, forKey: .executionMode)
        let dependsOnStageIDs = try container.decode([String].self, forKey: .dependsOnStageIDs)
        let capabilities = try container.decode([AutonomousCapability].self, forKey: .capabilities)

        self.init(
            stageID: stageID,
            kind: kind,
            displayName: displayName,
            task: task,
            taskProfileID: taskProfileID,
            suiteIDs: suiteIDs,
            seedCount: seedCount,
            episodesPerSuite: episodesPerSuite,
            generationLimit: generationLimit,
            convergenceGoal: convergenceGoal,
            executionMode: executionMode,
            dependsOnStageIDs: dependsOnStageIDs,
            capabilities: capabilities
        )
    }
}
