import Foundation

public struct ConsciousUnconsciousObservabilityArtifact: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 1
    public static let fileName = "conscious-unconscious-observability.json"

    public struct DescendingSnapshot: Sendable, Codable, Equatable {
        public let stepIndex: Int
        public let timestamp: Double
        public let source: String
        public let goalID: String?
        public let priority: Double
        public let inhibition: Double
        public let contextHash: String?

        public init(
            stepIndex: Int,
            timestamp: Double,
            source: String,
            goalID: String?,
            priority: Double,
            inhibition: Double,
            contextHash: String?
        ) {
            self.stepIndex = stepIndex
            self.timestamp = timestamp
            self.source = source
            self.goalID = goalID
            self.priority = priority
            self.inhibition = inhibition
            self.contextHash = contextHash
        }
    }

    public struct UpwardSummary: Sendable, Codable, Equatable {
        public let stepIndex: Int
        public let timestamp: Double
        public let channels: [ScalarChannel]

        public init(stepIndex: Int, timestamp: Double, channels: [ScalarChannel]) {
            self.stepIndex = stepIndex
            self.timestamp = timestamp
            self.channels = channels
        }
    }

    public struct ScalarChannel: Sendable, Codable, Equatable {
        public let name: String
        public let stableIndex: Int
        public let value: Double

        public init(name: String, stableIndex: Int, value: Double) {
            self.name = name
            self.stableIndex = stableIndex
            self.value = value
        }
    }

    public struct ArbitrationDecision: Sendable, Codable, Equatable {
        public let stepIndex: Int
        public let timestamp: Double
        public let coreDriveMagnitude: Double
        public let reflexCorrectionMagnitude: Double
        public let finalDriveMagnitude: Double
        public let reflexPreemptedDescendingBias: Bool
        public let reason: String

        public init(
            stepIndex: Int,
            timestamp: Double,
            coreDriveMagnitude: Double,
            reflexCorrectionMagnitude: Double,
            finalDriveMagnitude: Double,
            reflexPreemptedDescendingBias: Bool,
            reason: String
        ) {
            self.stepIndex = stepIndex
            self.timestamp = timestamp
            self.coreDriveMagnitude = coreDriveMagnitude
            self.reflexCorrectionMagnitude = reflexCorrectionMagnitude
            self.finalDriveMagnitude = finalDriveMagnitude
            self.reflexPreemptedDescendingBias = reflexPreemptedDescendingBias
            self.reason = reason
        }
    }

    public struct LatencyBudgetViolation: Sendable, Codable, Equatable {
        public let stepIndex: Int
        public let timestamp: Double
        public let path: String
        public let budgetMilliseconds: Double
        public let observedMilliseconds: Double
        public let reason: String

        public init(
            stepIndex: Int,
            timestamp: Double,
            path: String,
            budgetMilliseconds: Double,
            observedMilliseconds: Double,
            reason: String
        ) {
            self.stepIndex = stepIndex
            self.timestamp = timestamp
            self.path = path
            self.budgetMilliseconds = budgetMilliseconds
            self.observedMilliseconds = observedMilliseconds
            self.reason = reason
        }
    }

    public let schemaVersion: Int
    public let runID: String
    public let scenarioID: String
    public let seed: UInt64?
    public let timeStep: Double
    public let descendingSnapshots: [DescendingSnapshot]
    public let upwardSummaries: [UpwardSummary]
    public let arbitrationDecisions: [ArbitrationDecision]
    public let latencyBudgetViolations: [LatencyBudgetViolation]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        runID: String,
        scenarioID: String,
        seed: UInt64?,
        timeStep: Double,
        descendingSnapshots: [DescendingSnapshot],
        upwardSummaries: [UpwardSummary],
        arbitrationDecisions: [ArbitrationDecision],
        latencyBudgetViolations: [LatencyBudgetViolation] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.scenarioID = scenarioID
        self.seed = seed
        self.timeStep = timeStep
        self.descendingSnapshots = descendingSnapshots
        self.upwardSummaries = upwardSummaries
        self.arbitrationDecisions = arbitrationDecisions
        self.latencyBudgetViolations = latencyBudgetViolations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            runID: try container.decode(String.self, forKey: .runID),
            scenarioID: try container.decode(String.self, forKey: .scenarioID),
            seed: try container.decodeIfPresent(UInt64.self, forKey: .seed),
            timeStep: try container.decode(Double.self, forKey: .timeStep),
            descendingSnapshots: try container.decode(
                [DescendingSnapshot].self,
                forKey: .descendingSnapshots
            ),
            upwardSummaries: try container.decode([UpwardSummary].self, forKey: .upwardSummaries),
            arbitrationDecisions: try container.decode(
                [ArbitrationDecision].self,
                forKey: .arbitrationDecisions
            ),
            latencyBudgetViolations: try container.decodeIfPresent(
                [LatencyBudgetViolation].self,
                forKey: .latencyBudgetViolations
            ) ?? []
        )
        try ConsciousUnconsciousObservabilityArtifactValidator().validate(self)
    }
}
