import Foundation

public struct TrainingRunProgressEvent: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let event: String
    public let status: String?
    public let exitCode: Int?
    public let phase: String?
    public let seed: String?
    public let generationIndex: Int?
    public let candidateID: String?
    public let progressFraction: Double?
    public let fitness: Double?
    public let rewardAverage: Double?
    public let taskPassRate: Double?
    public let safetyViolationRate: Double?
    public let holdTimeRatio: Double?
    public let altitudeErrorRatio: Double?
    public let workerThroughput: Double?
    public let gpuAcceleration: Bool?
    public let tensorWorldBatch: Bool?
    public let tensorSummary: Bool?
    public let vectorizedPopulationSize: Int?
    public let vectorizedWorldCount: Int?
    public let vectorizedHistoryLength: Int?
    public let vectorizedObservationDimension: Int?
    public let vectorizedActionDimension: Int?
    public let failureReasons: [String]
    public let bestCandidateID: String?
    public let accepted: Bool?
    public let path: String?
    public let message: String?

    public init(
        timestamp: Date = Date(),
        event: String,
        status: String? = nil,
        exitCode: Int? = nil,
        phase: String? = nil,
        seed: String? = nil,
        generationIndex: Int? = nil,
        candidateID: String? = nil,
        progressFraction: Double? = nil,
        fitness: Double? = nil,
        rewardAverage: Double? = nil,
        taskPassRate: Double? = nil,
        safetyViolationRate: Double? = nil,
        holdTimeRatio: Double? = nil,
        altitudeErrorRatio: Double? = nil,
        workerThroughput: Double? = nil,
        gpuAcceleration: Bool? = nil,
        tensorWorldBatch: Bool? = nil,
        tensorSummary: Bool? = nil,
        vectorizedPopulationSize: Int? = nil,
        vectorizedWorldCount: Int? = nil,
        vectorizedHistoryLength: Int? = nil,
        vectorizedObservationDimension: Int? = nil,
        vectorizedActionDimension: Int? = nil,
        failureReasons: [String] = [],
        bestCandidateID: String? = nil,
        accepted: Bool? = nil,
        path: String? = nil,
        message: String? = nil
    ) {
        self.timestamp = timestamp
        self.event = event
        self.status = status
        self.exitCode = exitCode
        self.phase = phase
        self.seed = seed
        self.generationIndex = generationIndex
        self.candidateID = candidateID
        self.progressFraction = progressFraction
        self.fitness = fitness
        self.rewardAverage = rewardAverage
        self.taskPassRate = taskPassRate
        self.safetyViolationRate = safetyViolationRate
        self.holdTimeRatio = holdTimeRatio
        self.altitudeErrorRatio = altitudeErrorRatio
        self.workerThroughput = workerThroughput
        self.gpuAcceleration = gpuAcceleration
        self.tensorWorldBatch = tensorWorldBatch
        self.tensorSummary = tensorSummary
        self.vectorizedPopulationSize = vectorizedPopulationSize
        self.vectorizedWorldCount = vectorizedWorldCount
        self.vectorizedHistoryLength = vectorizedHistoryLength
        self.vectorizedObservationDimension = vectorizedObservationDimension
        self.vectorizedActionDimension = vectorizedActionDimension
        self.failureReasons = failureReasons
        self.bestCandidateID = bestCandidateID
        self.accepted = accepted
        self.path = path
        self.message = message
    }
}
