import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

/// One journaled training iteration, serialized as a single compact JSON line
/// in `iterations.jsonl`.
///
/// Records are appended in strict iteration order and are never rewritten.
/// All optional groups may be omitted when not applicable to the iteration.
public struct TrainingRunIterationRecord: Sendable, Codable, Equatable {
    /// Curriculum horizon state at this iteration.
    public struct HorizonState: Sendable, Codable, Equatable {
        public let supportHorizon: Int
        public let frontierHorizon: Int
        public let fullHorizon: Int
        public let mode: String

        public init(supportHorizon: Int, frontierHorizon: Int, fullHorizon: Int, mode: String) {
            self.supportHorizon = supportHorizon
            self.frontierHorizon = frontierHorizon
            self.fullHorizon = fullHorizon
            self.mode = mode
        }
    }

    /// Candidate accept/reject decision with typed rejection reasons and
    /// per-horizon health metrics.
    public struct CandidateDecision: Sendable, Codable, Equatable {
        public let accepted: Bool
        public let rejectionReasons: [String]
        public let horizonHealth: [String: Double]

        public init(accepted: Bool, rejectionReasons: [String], horizonHealth: [String: Double]) {
            self.accepted = accepted
            self.rejectionReasons = rejectionReasons
            self.horizonHealth = horizonHealth
        }
    }

    /// Evaluation metrics gathered at a specific horizon.
    public struct EvaluationRecord: Sendable, Codable, Equatable {
        public let evaluationHorizon: Int
        public let metrics: [String: Double]

        public init(evaluationHorizon: Int, metrics: [String: Double]) {
            self.evaluationHorizon = evaluationHorizon
            self.metrics = metrics
        }
    }

    /// One failed episode observed during rollout or evaluation.
    public struct FailureEpisode: Sendable, Codable, Equatable {
        public let scenario: String
        public let seed: UInt64
        public let terminalStep: Int
        public let reason: String

        public init(scenario: String, seed: UInt64, terminalStep: Int, reason: String) {
            self.scenario = scenario
            self.seed = seed
            self.terminalStep = terminalStep
            self.reason = reason
        }
    }

    /// Reference to a checkpoint written during this iteration.
    public struct CheckpointReference: Sendable, Codable, Equatable {
        public let path: String
        public let sha256Digest: String

        public init(path: String, sha256Digest: String) {
            self.path = path
            self.sha256Digest = sha256Digest
        }
    }

    /// Zero-based, strictly increasing iteration index.
    public let iteration: Int
    public let recordedAt: Date
    public let horizon: HorizonState?
    public let decision: CandidateDecision?
    public let evaluation: EvaluationRecord?
    public let failureEpisodes: [FailureEpisode]
    public let phaseTimings: [String: Double]
    public let environmentSample: [String: Double]
    public let checkpoint: CheckpointReference?

    public init(
        iteration: Int,
        recordedAt: Date,
        horizon: HorizonState? = nil,
        decision: CandidateDecision? = nil,
        evaluation: EvaluationRecord? = nil,
        failureEpisodes: [FailureEpisode] = [],
        phaseTimings: [String: Double] = [:],
        environmentSample: [String: Double] = [:],
        checkpoint: CheckpointReference? = nil
    ) {
        self.iteration = iteration
        self.recordedAt = recordedAt
        self.horizon = horizon
        self.decision = decision
        self.evaluation = evaluation
        self.failureEpisodes = failureEpisodes
        self.phaseTimings = phaseTimings
        self.environmentSample = environmentSample
        self.checkpoint = checkpoint
    }
}
