import Foundation

public struct EvolutionCandidateArtifactRetentionRecord: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public struct Deletion: Codable, Sendable, Equatable {
        public let candidateID: String
        public let generationIndex: Int
        public let relativePath: String
        public let checkpointReference: EvolutionCheckpointReference
        public let reason: String

        public init(
            candidateID: String,
            generationIndex: Int,
            relativePath: String,
            checkpointReference: EvolutionCheckpointReference,
            reason: String
        ) {
            self.candidateID = candidateID
            self.generationIndex = generationIndex
            self.relativePath = relativePath
            self.checkpointReference = checkpointReference
            self.reason = reason
        }
    }

    public let schemaVersion: Int
    public let runID: String
    public let generationIndex: Int
    public let protectedCheckpointPaths: [String]
    public let deletions: [Deletion]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        runID: String,
        generationIndex: Int,
        protectedCheckpointPaths: [String],
        deletions: [Deletion]
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.generationIndex = generationIndex
        self.protectedCheckpointPaths = protectedCheckpointPaths
        self.deletions = deletions
    }
}
