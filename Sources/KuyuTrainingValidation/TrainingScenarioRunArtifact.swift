public struct TrainingScenarioRunArtifact: Sendable, Codable, Equatable {
    public static let fileName = "scenario-runs.jsonl"

    public let runID: String
    public let iteration: Int
    public let summary: TrainingScenarioRunSummary
    public let logCount: Int
    public let terminalFactCount: Int

    public init(
        runID: String,
        iteration: Int,
        summary: TrainingScenarioRunSummary,
        logCount: Int,
        terminalFactCount: Int
    ) {
        self.runID = runID
        self.iteration = iteration
        self.summary = summary
        self.logCount = logCount
        self.terminalFactCount = terminalFactCount
    }

    public init(
        runID: String,
        iteration: Int,
        output: TrainingScenarioRunOutput
    ) {
        self.init(
            runID: runID,
            iteration: iteration,
            summary: output.summary,
            logCount: output.logs.count,
            terminalFactCount: output.terminalFactsByScenarioKey.count
        )
    }
}
