import Foundation

public struct EvolutionCandidateEvaluationTrace: Sendable, Codable, Equatable {
    public let runID: String
    public let generationIndex: Int
    public let candidateID: String
    public let requestedConcurrency: Int
    public let activeEvaluationCountAtStart: Int
    public let startedAt: Date
    public let completedAt: Date
    public let durationSeconds: Double

    public init(
        runID: String,
        generationIndex: Int,
        candidateID: String,
        requestedConcurrency: Int,
        activeEvaluationCountAtStart: Int,
        startedAt: Date,
        completedAt: Date
    ) {
        self.runID = runID
        self.generationIndex = max(0, generationIndex)
        self.candidateID = candidateID
        self.requestedConcurrency = max(1, requestedConcurrency)
        self.activeEvaluationCountAtStart = max(1, activeEvaluationCountAtStart)
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationSeconds = max(0, completedAt.timeIntervalSince(startedAt))
    }
}
