import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public enum CheckpointDecisionState: String, Sendable, Codable, Equatable {
    case accepted
    case rejected
    case staged
    case skipped
    case failed
}

public struct CheckpointDecision: Sendable, Codable, Equatable {
    public let runID: String
    public let state: CheckpointDecisionState
    public let reason: String
    public let candidateCheckpointID: String?
    public let candidateCheckpointURL: URL?
    public let publishedCheckpointURL: URL?
    public let decidedAt: Date

    public init(
        runID: String,
        state: CheckpointDecisionState,
        reason: String,
        candidateCheckpointID: String? = nil,
        candidateCheckpointURL: URL? = nil,
        publishedCheckpointURL: URL? = nil,
        decidedAt: Date = Date()
    ) {
        self.runID = runID
        self.state = state
        self.reason = reason
        self.candidateCheckpointID = candidateCheckpointID
        self.candidateCheckpointURL = candidateCheckpointURL
        self.publishedCheckpointURL = publishedCheckpointURL
        self.decidedAt = decidedAt
    }
}

public struct CheckpointAcceptancePolicy: Sendable {
    public init() {}

    public func decision(
        runID: String,
        convergence: ConvergenceSummary,
        candidateCheckpointID: String?,
        candidateCheckpointURL: URL?
    ) -> CheckpointDecision {
        guard let candidateCheckpointID else {
            return CheckpointDecision(
                runID: runID,
                state: .skipped,
                reason: "no-candidate-checkpoint",
                candidateCheckpointID: nil,
                candidateCheckpointURL: candidateCheckpointURL
            )
        }
        guard convergence.accepted else {
            return CheckpointDecision(
                runID: runID,
                state: .rejected,
                reason: convergence.reason,
                candidateCheckpointID: candidateCheckpointID,
                candidateCheckpointURL: candidateCheckpointURL
            )
        }
        return CheckpointDecision(
            runID: runID,
            state: .accepted,
            reason: "accepted",
            candidateCheckpointID: candidateCheckpointID,
            candidateCheckpointURL: candidateCheckpointURL
        )
    }
}

public struct CheckpointRepository: Sendable {
    public init() {}

    public func publish(
        decision: CheckpointDecision,
        under artifactDirectory: URL
    ) throws -> CheckpointDecision {
        switch decision.state {
        case .accepted:
            guard let candidateURL = decision.candidateCheckpointURL else {
                return CheckpointDecision(
                    runID: decision.runID,
                    state: .skipped,
                    reason: "no-candidate-checkpoint-url",
                    candidateCheckpointID: decision.candidateCheckpointID,
                    candidateCheckpointURL: nil,
                    publishedCheckpointURL: nil,
                    decidedAt: decision.decidedAt
                )
            }
            let destination = artifactDirectory
                .appendingPathComponent("checkpoints", isDirectory: true)
                .appendingPathComponent("accepted", isDirectory: true)
            try replaceItem(at: destination, with: candidateURL)
            return CheckpointDecision(
                runID: decision.runID,
                state: .accepted,
                reason: decision.reason,
                candidateCheckpointID: decision.candidateCheckpointID,
                candidateCheckpointURL: candidateURL,
                publishedCheckpointURL: destination,
                decidedAt: decision.decidedAt
            )
        case .rejected:
            let destination = artifactDirectory
                .appendingPathComponent("checkpoints", isDirectory: true)
                .appendingPathComponent("rejected", isDirectory: true)
                .appendingPathComponent(decision.runID, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            return CheckpointDecision(
                runID: decision.runID,
                state: .rejected,
                reason: decision.reason,
                candidateCheckpointID: decision.candidateCheckpointID,
                candidateCheckpointURL: decision.candidateCheckpointURL,
                publishedCheckpointURL: destination,
                decidedAt: decision.decidedAt
            )
        case .staged, .skipped, .failed:
            return decision
        }
    }

    private func replaceItem(at destination: URL, with source: URL) throws {
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".\(destination.lastPathComponent)-\(UUID().uuidString)", isDirectory: true)
        if FileManager.default.fileExists(atPath: temporary.path) {
            try FileManager.default.removeItem(at: temporary)
        }
        try FileManager.default.copyItem(at: source, to: temporary)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
