public struct TrainingProjectObservabilityArtifactEvidence: Sendable, Codable, Equatable {
    public let runID: String
    public let scenarioID: String
    public let seed: UInt64?
    public let descendingSnapshotCount: Int
    public let upwardSummaryCount: Int
    public let arbitrationDecisionCount: Int
    public let latencyBudgetViolationCount: Int
    public let path: String

    public init(
        runID: String,
        scenarioID: String,
        seed: UInt64?,
        descendingSnapshotCount: Int,
        upwardSummaryCount: Int,
        arbitrationDecisionCount: Int,
        latencyBudgetViolationCount: Int,
        path: String
    ) {
        self.runID = runID
        self.scenarioID = scenarioID
        self.seed = seed
        self.descendingSnapshotCount = descendingSnapshotCount
        self.upwardSummaryCount = upwardSummaryCount
        self.arbitrationDecisionCount = arbitrationDecisionCount
        self.latencyBudgetViolationCount = latencyBudgetViolationCount
        self.path = path
    }

    public init(
        artifact: ConsciousUnconsciousObservabilityArtifact,
        path: String
    ) {
        self.init(
            runID: artifact.runID,
            scenarioID: artifact.scenarioID,
            seed: artifact.seed,
            descendingSnapshotCount: artifact.descendingSnapshots.count,
            upwardSummaryCount: artifact.upwardSummaries.count,
            arbitrationDecisionCount: artifact.arbitrationDecisions.count,
            latencyBudgetViolationCount: artifact.latencyBudgetViolations.count,
            path: path
        )
    }
}
