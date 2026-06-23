import Foundation

public struct TrainingEvaluationContext<Observation: Sendable, Action: Sendable>: Sendable {
    public let runID: String
    public let taskProfileID: String
    public let artifactRoot: URL
    public let seed: UInt64
    public let observationPrototype: Observation?
    public let actionPrototype: Action?
    public let workerCount: Int

    public init(
        runID: String,
        taskProfileID: String,
        artifactRoot: URL,
        seed: UInt64,
        observationPrototype: Observation? = nil,
        actionPrototype: Action? = nil,
        workerCount: Int = 1
    ) {
        self.runID = runID
        self.taskProfileID = taskProfileID
        self.artifactRoot = artifactRoot
        self.seed = seed
        self.observationPrototype = observationPrototype
        self.actionPrototype = actionPrototype
        self.workerCount = max(1, workerCount)
    }
}
