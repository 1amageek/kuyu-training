import KuyuCore

public struct RolloutEpisode: Sendable, Codable, Equatable {
    public let episodeId: String
    public let scenarioId: String
    public let seed: UInt64
    public let workerIndex: Int
    public let policyId: String
    public let configHash: String
    public let robotManifestID: String?
    public let rewardDescriptor: RewardDescriptor?
    public let rewardSum: Double
    public let done: Bool
    public let truncated: Bool
    public let terminalReason: String?
    public let failureReason: String?
    public let failureTime: Double?
    public let stepCount: Int
    public let workerCount: Int?
    public let maxSteps: Int?
    public let durationSeconds: Double
    public let cancelled: Bool
    public let steps: [EnvironmentStep]
    public let transitions: [RolloutTransition]?
    public let physicsTimeStep: Double?
    public let controlPeriodSteps: UInt64?
    public let taskReference: TrainingTaskReferenceMetadata?

    public init(
        episodeId: String,
        scenarioId: String,
        seed: UInt64,
        workerIndex: Int,
        policyId: String,
        configHash: String,
        robotManifestID: String?,
        rewardDescriptor: RewardDescriptor? = nil,
        rewardSum: Double,
        done: Bool,
        truncated: Bool,
        terminalReason: String?,
        failureReason: String?,
        failureTime: Double?,
        stepCount: Int,
        workerCount: Int? = nil,
        maxSteps: Int? = nil,
        durationSeconds: Double,
        cancelled: Bool = false,
        steps: [EnvironmentStep],
        transitions: [RolloutTransition]? = nil,
        physicsTimeStep: Double? = nil,
        controlPeriodSteps: UInt64? = nil,
        taskReference: TrainingTaskReferenceMetadata? = nil
    ) {
        self.episodeId = episodeId
        self.scenarioId = scenarioId
        self.seed = seed
        self.workerIndex = workerIndex
        self.policyId = policyId
        self.configHash = configHash
        self.robotManifestID = robotManifestID
        self.rewardDescriptor = rewardDescriptor
        self.rewardSum = rewardSum
        self.done = done
        self.truncated = truncated
        self.terminalReason = terminalReason
        self.failureReason = failureReason
        self.failureTime = failureTime
        self.stepCount = stepCount
        self.workerCount = workerCount
        self.maxSteps = maxSteps
        self.durationSeconds = durationSeconds
        self.cancelled = cancelled
        self.steps = steps
        self.transitions = transitions
        self.physicsTimeStep = physicsTimeStep
        self.controlPeriodSteps = controlPeriodSteps
        self.taskReference = taskReference
    }
}
