import Foundation
import KuyuTrainingContracts

public struct TrainingRunSummaryOutcomeArtifact: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 2
    public static let fileName = "training-run-summary-outcome.json"
    public static let workerDirectoryName = "TRAINING_RUN_WORKER_OUTCOMES"

    public let schemaVersion: Int
    public let completedAt: Date
    public let workerAttemptIdentity: TrainingRunWorkerAttemptIdentity?
    public let summary: TrainingRunSummary

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        completedAt: Date,
        workerAttemptIdentity: TrainingRunWorkerAttemptIdentity? = nil,
        summary: TrainingRunSummary
    ) {
        self.schemaVersion = schemaVersion
        self.completedAt = completedAt
        self.workerAttemptIdentity = workerAttemptIdentity
        self.summary = summary
    }
}
