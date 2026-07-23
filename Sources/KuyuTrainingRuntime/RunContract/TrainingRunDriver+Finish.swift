import Foundation

public extension TrainingRunDriver {
    @discardableResult
    func finish(result: TrainingRunResult) throws -> FinishDisposition {
        let classification = TrainingRunResultTerminalClassifier().classify(result: result)
        switch classification.status {
        case .accepted:
            try finishCompleted(acceptedCheckpointPath: classification.acceptedCheckpointPath)
            return .completed
        case .rejected:
            try finishCompleted(acceptedCheckpointPath: nil)
            return .completed
        case .cancelled:
            try finishCancelled(acceptedCheckpointPath: nil)
            return .cancelled
        case .failed, .incomplete:
            finishFailedReportingSecondaryFailure(reason: classification.reason)
            return .failed(reason: classification.reason)
        }
    }

    func finishCompleted(acceptedCheckpointPath: String?) throws {
        try finish(status: .completed, acceptedCheckpointPath: acceptedCheckpointPath, failureReason: nil)
    }

    func finishCancelled(acceptedCheckpointPath: String?) throws {
        try finish(status: .cancelled, acceptedCheckpointPath: acceptedCheckpointPath, failureReason: nil)
    }

    /// Best-effort failure outcome for error-propagation paths. Never throws:
    /// the original training error must surface, not be masked by a secondary
    /// journaling failure — which is reported explicitly instead.
    func finishFailedReportingSecondaryFailure(reason: String) {
        do {
            try finish(status: .failed, acceptedCheckpointPath: nil, failureReason: reason)
        } catch {
            print("TRAINING-RUN WARNING: failed to write failure outcome for run=\(runIDString): \(error)")
        }
    }

    private func finish(
        status: TrainingRunLifecycleStatus,
        acceptedCheckpointPath: String?,
        failureReason: String?
    ) throws {
        guard !isFinished else { return }
        let finalIteration = writer.nextIteration > 0 ? writer.nextIteration - 1 : nil
        try writer.writeOutcome(
            TrainingRunOutcome(
                status: status,
                updatedAt: Date(),
                finalIteration: finalIteration,
                failureReason: failureReason,
                acceptedCheckpointPath: acceptedCheckpointPath
            )
        )
        isFinished = true
    }
}
