import Foundation
import KuyuTrainingContracts

public struct CandidateEvaluation<Candidate: Sendable, Fitness: Comparable & Sendable>: Sendable {
    public let candidate: Candidate
    public let candidateID: String
    public let fitness: Fitness
    public let rewardAverage: Double?
    public let taskPassRate: Double?
    public let holdTimeRatio: Double?
    public let altitudeErrorRatio: Double?
    public let safetyRate: Double?
    public let failureReasons: [String]
    public let artifactRoot: URL?

    public init(
        candidate: Candidate,
        candidateID: String,
        fitness: Fitness,
        rewardAverage: Double? = nil,
        taskPassRate: Double? = nil,
        holdTimeRatio: Double? = nil,
        altitudeErrorRatio: Double? = nil,
        safetyRate: Double? = nil,
        failureReasons: [String] = [],
        artifactRoot: URL? = nil
    ) {
        self.candidate = candidate
        self.candidateID = candidateID
        self.fitness = fitness
        self.rewardAverage = rewardAverage
        self.taskPassRate = taskPassRate
        self.holdTimeRatio = holdTimeRatio
        self.altitudeErrorRatio = altitudeErrorRatio
        self.safetyRate = safetyRate
        self.failureReasons = failureReasons
        self.artifactRoot = artifactRoot
    }
}
