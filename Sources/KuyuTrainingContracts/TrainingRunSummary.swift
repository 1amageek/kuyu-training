import Foundation

public struct TrainingRunSummary: Sendable, Codable, Equatable {
    public let runID: TrainingRunID
    public let artifactRoot: URL
    public let terminalState: TrainingRunTerminalState
    public let acceptedCheckpoint: ModelBundleReference?
    public let generationCount: Int
    public let candidateCount: Int
    public let failureReasons: [String]

    public init(
        runID: TrainingRunID,
        artifactRoot: URL,
        terminalState: TrainingRunTerminalState,
        acceptedCheckpoint: ModelBundleReference? = nil,
        generationCount: Int = 0,
        candidateCount: Int = 0,
        failureReasons: [String] = []
    ) {
        self.runID = runID
        self.artifactRoot = artifactRoot
        self.terminalState = terminalState
        self.acceptedCheckpoint = acceptedCheckpoint
        self.generationCount = max(0, generationCount)
        self.candidateCount = max(0, candidateCount)
        self.failureReasons = failureReasons
    }
}
