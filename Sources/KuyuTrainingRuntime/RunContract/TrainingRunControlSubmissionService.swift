import Foundation

public struct TrainingRunControlSubmissionService: Sendable {
    public init() {}

    public func submit(
        reader: TrainingRunArchiveReader,
        action: TrainingRunControlAction,
        requestedBy: String,
        requestedAt: Date = Date()
    ) throws -> TrainingRunControlSubmission {
        let liveness = try reader.liveness()
        try validate(liveness: liveness, runID: reader.runID.rawValue, action: action)
        let sequence = ((try reader.latestControlSequence()) ?? 0) + 1
        let command = TrainingRunControlCommand(
            sequence: sequence,
            action: action,
            requestedAt: requestedAt,
            requestedBy: requestedBy
        )
        try reader.submitControlCommand(command)
        return TrainingRunControlSubmission(command: command, liveness: liveness)
    }

    public func validate(
        liveness: TrainingRunLiveness,
        runID: String,
        action: TrainingRunControlAction
    ) throws {
        switch liveness {
        case .finished(let status):
            throw TrainingRunControlSubmissionError.runAlreadyFinished(
                runID: runID,
                status: status,
                action: action
            )
        case .interrupted:
            throw TrainingRunControlSubmissionError.runInterrupted(
                runID: runID,
                action: action
            )
        case .paused(let processAlive) where !processAlive:
            throw TrainingRunControlSubmissionError.pausedWriterDead(
                runID: runID,
                action: action
            )
        case .live, .paused:
            return
        }
    }
}
