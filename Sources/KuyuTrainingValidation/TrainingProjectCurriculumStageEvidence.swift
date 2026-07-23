import KuyuTrainingContracts

public struct TrainingProjectCurriculumStageEvidence: Sendable, Codable, Equatable {
    public let stageID: String
    public let kind: AutonomousTrainingStageKind
    public let task: String
    public let taskProfileID: String?
    public let producedArtifactID: String?
    public let suiteIDs: [Int]
    public let seedCount: Int
    public let episodesPerSuite: Int
    public let generationLimit: Int
    public let dependsOnStageIDs: [String]

    public init(
        stageID: String,
        kind: AutonomousTrainingStageKind,
        task: String,
        taskProfileID: String?,
        producedArtifactID: String? = nil,
        suiteIDs: [Int],
        seedCount: Int,
        episodesPerSuite: Int,
        generationLimit: Int,
        dependsOnStageIDs: [String]
    ) {
        self.stageID = stageID
        self.kind = kind
        self.task = task
        self.taskProfileID = taskProfileID
        self.producedArtifactID = producedArtifactID
        self.suiteIDs = suiteIDs
        self.seedCount = seedCount
        self.episodesPerSuite = episodesPerSuite
        self.generationLimit = generationLimit
        self.dependsOnStageIDs = dependsOnStageIDs
    }

    public init(stage: LearningProjectTrainingStage) {
        self.init(
            stageID: stage.stageID,
            kind: stage.kind,
            task: stage.task,
            taskProfileID: stage.taskProfileID,
            suiteIDs: stage.suiteIDs,
            seedCount: stage.seedCount,
            episodesPerSuite: stage.episodesPerSuite,
            generationLimit: stage.generationLimit,
            dependsOnStageIDs: stage.dependsOnStageIDs
        )
    }

    public init(
        stage: LearningProjectTrainingStage,
        producedArtifactID: String
    ) {
        self.init(
            stageID: stage.stageID,
            kind: stage.kind,
            task: stage.task,
            taskProfileID: stage.taskProfileID,
            producedArtifactID: producedArtifactID,
            suiteIDs: stage.suiteIDs,
            seedCount: stage.seedCount,
            episodesPerSuite: stage.episodesPerSuite,
            generationLimit: stage.generationLimit,
            dependsOnStageIDs: stage.dependsOnStageIDs
        )
    }
}
