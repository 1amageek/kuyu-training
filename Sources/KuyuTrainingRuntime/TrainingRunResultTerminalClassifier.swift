import Foundation

public struct TrainingRunResultTerminalClassifier: Sendable {
    public struct Classification: Sendable, Equatable {
        public enum Status: String, Sendable, Equatable {
            case accepted
            case rejected
            case cancelled
            case failed
            case incomplete
        }

        public let status: Status
        public let reason: String
        public let acceptedCheckpointPath: String?

        public var accepted: Bool {
            status == .accepted
        }

        public init(status: Status, reason: String, acceptedCheckpointPath: String? = nil) {
            self.status = status
            self.reason = reason
            self.acceptedCheckpointPath = acceptedCheckpointPath
        }
    }

    public init() {}

    public func classify(result: TrainingRunResult) -> Classification {
        guard result.convergence.runID == result.manifest.runID else {
            return Classification(
                status: .rejected,
                reason: "run-id-mismatch: convergence=\(result.convergence.runID) manifest=\(result.manifest.runID)"
            )
        }
        guard result.checkpointDecision.runID == result.manifest.runID else {
            return Classification(
                status: .rejected,
                reason: "run-id-mismatch: checkpointDecision=\(result.checkpointDecision.runID) manifest=\(result.manifest.runID)"
            )
        }

        switch result.manifest.terminalState {
        case .completed:
            guard result.convergence.accepted else {
                return Classification(status: .rejected, reason: result.convergence.reason)
            }
            guard result.checkpointDecision.state == .accepted else {
                return Classification(status: .rejected, reason: result.checkpointDecision.reason)
            }
            return Classification(
                status: .accepted,
                reason: result.checkpointDecision.reason,
                acceptedCheckpointPath: result.checkpointDecision.publishedCheckpointURL?.path
                    ?? result.checkpointDecision.candidateCheckpointURL?.path
            )
        case .rejected:
            return Classification(
                status: .rejected,
                reason: result.manifest.failureReason ?? result.convergence.reason
            )
        case .cancelled:
            return Classification(
                status: .cancelled,
                reason: result.manifest.failureReason ?? "cancelled"
            )
        case .failed:
            return Classification(
                status: .failed,
                reason: result.manifest.failureReason ?? result.convergence.reason
            )
        case .running:
            return Classification(
                status: .incomplete,
                reason: result.manifest.failureReason ?? "run-not-terminal"
            )
        }
    }
}
