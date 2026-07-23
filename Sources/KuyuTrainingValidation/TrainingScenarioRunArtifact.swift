import KuyuCore

public struct TrainingScenarioRunArtifact: Sendable, Codable, Equatable {
    public static let fileName = "scenario-runs.jsonl"

    public let runID: String
    public let iteration: Int
    public let summary: TrainingScenarioRunSummary
    public let logCount: Int
    public let terminalFactCount: Int
    public let scenarioKeys: [ScenarioKey]

    public init(
        runID: String,
        iteration: Int,
        summary: TrainingScenarioRunSummary,
        logCount: Int,
        terminalFactCount: Int,
        scenarioKeys: [ScenarioKey] = []
    ) {
        self.runID = runID
        self.iteration = iteration
        self.summary = summary
        self.logCount = logCount
        self.terminalFactCount = terminalFactCount
        self.scenarioKeys = scenarioKeys
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
            terminalFactCount: output.terminalFactsByScenarioKey.count,
            scenarioKeys: output.logs.map(\.key).sorted(by: Self.scenarioKeyPrecedes)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case runID
        case iteration
        case summary
        case logCount
        case terminalFactCount
        case scenarioKeys
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runID = try container.decode(String.self, forKey: .runID)
        iteration = try container.decode(Int.self, forKey: .iteration)
        summary = try container.decode(TrainingScenarioRunSummary.self, forKey: .summary)
        logCount = try container.decode(Int.self, forKey: .logCount)
        terminalFactCount = try container.decode(Int.self, forKey: .terminalFactCount)
        scenarioKeys = try container.decodeIfPresent([ScenarioKey].self, forKey: .scenarioKeys) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(runID, forKey: .runID)
        try container.encode(iteration, forKey: .iteration)
        try container.encode(summary, forKey: .summary)
        try container.encode(logCount, forKey: .logCount)
        try container.encode(terminalFactCount, forKey: .terminalFactCount)
        if !scenarioKeys.isEmpty {
            try container.encode(scenarioKeys, forKey: .scenarioKeys)
        }
    }

    private static func scenarioKeyPrecedes(_ lhs: ScenarioKey, _ rhs: ScenarioKey) -> Bool {
        if lhs.scenarioId.rawValue == rhs.scenarioId.rawValue {
            return lhs.seed.rawValue < rhs.seed.rawValue
        }
        return lhs.scenarioId.rawValue < rhs.scenarioId.rawValue
    }
}
