import Foundation

public enum TrainingRunLogLevel: String, Sendable, Codable, Equatable {
    case info
    case success
    case warning
    case failure
}

public struct TrainingRunLogEvent: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let level: TrainingRunLogLevel
    public let phase: String
    public let message: String
    public let seed: String?
    public let generationIndex: Int?
    public let candidateID: String?
    public let progressFraction: Double?
    public let metadata: [String: String]

    public init(
        timestamp: Date = Date(),
        level: TrainingRunLogLevel,
        phase: String,
        message: String,
        seed: String? = nil,
        generationIndex: Int? = nil,
        candidateID: String? = nil,
        progressFraction: Double? = nil,
        metadata: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.level = level
        self.phase = phase
        self.message = message
        self.seed = seed
        self.generationIndex = generationIndex
        self.candidateID = candidateID
        self.progressFraction = progressFraction
        self.metadata = metadata
    }
}
