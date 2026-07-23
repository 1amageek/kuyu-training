import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public struct TrainingProbeManifest: Sendable, Codable, Equatable {
    public let probeID: String
    public let trainingRunID: String
    public let startedAt: Date
    public let completedAt: Date?
    public let terminalState: LearningRunTerminalState
    public let failureReason: String?
    public let minScoreDelta: Double
    public let requireAcceptedCheckpoint: Bool
    public let requireTeacherPass: Bool
    public let requireTrainedPass: Bool
    public let sourceCheckpointURL: URL?

    public init(
        probeID: String,
        trainingRunID: String,
        startedAt: Date,
        completedAt: Date? = nil,
        terminalState: LearningRunTerminalState,
        failureReason: String? = nil,
        minScoreDelta: Double = 0,
        requireAcceptedCheckpoint: Bool = true,
        requireTeacherPass: Bool = true,
        requireTrainedPass: Bool = true,
        sourceCheckpointURL: URL? = nil
    ) {
        self.probeID = probeID
        self.trainingRunID = trainingRunID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.terminalState = terminalState
        self.failureReason = failureReason
        self.minScoreDelta = minScoreDelta
        self.requireAcceptedCheckpoint = requireAcceptedCheckpoint
        self.requireTeacherPass = requireTeacherPass
        self.requireTrainedPass = requireTrainedPass
        self.sourceCheckpointURL = sourceCheckpointURL
    }

    public func completed(
        at completedAt: Date,
        terminalState: LearningRunTerminalState,
        failureReason: String?
    ) -> TrainingProbeManifest {
        TrainingProbeManifest(
            probeID: probeID,
            trainingRunID: trainingRunID,
            startedAt: startedAt,
            completedAt: completedAt,
            terminalState: terminalState,
            failureReason: failureReason,
            minScoreDelta: minScoreDelta,
            requireAcceptedCheckpoint: requireAcceptedCheckpoint,
            requireTeacherPass: requireTeacherPass,
            requireTrainedPass: requireTrainedPass,
            sourceCheckpointURL: sourceCheckpointURL
        )
    }
}
