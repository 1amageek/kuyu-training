public struct ReinforcementTrainingResult<Checkpoint: Sendable>: Sendable {
    public let checkpoint: Checkpoint
    public let rewardAverage: Double
    public let loss: Double?
    public let failureReasons: [String]

    public init(
        checkpoint: Checkpoint,
        rewardAverage: Double,
        loss: Double? = nil,
        failureReasons: [String] = []
    ) {
        self.checkpoint = checkpoint
        self.rewardAverage = rewardAverage
        self.loss = loss
        self.failureReasons = failureReasons
    }
}
