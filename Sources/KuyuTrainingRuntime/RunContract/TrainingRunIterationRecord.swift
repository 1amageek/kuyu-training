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
    /// health metrics for the policy retained after the decision.
    public struct CandidateDecision: Sendable, Codable, Equatable {
        public let accepted: Bool
        public let materiallyImproved: Bool
        public let rejectionReasons: [String]
        public let progressSignals: [String]
        public let progressRejectionReasons: [String]
        public let horizonHealth: [String: Double]

        public init(
            accepted: Bool,
            materiallyImproved: Bool,
            rejectionReasons: [String],
            progressSignals: [String],
            progressRejectionReasons: [String],
            horizonHealth: [String: Double]
        ) {
            self.accepted = accepted
            self.materiallyImproved = materiallyImproved
            self.rejectionReasons = rejectionReasons
            self.progressSignals = progressSignals
            self.progressRejectionReasons = progressRejectionReasons
            self.horizonHealth = horizonHealth
        }
    }

    /// Evaluation metrics gathered at a specific horizon.
    public struct EvaluationRecord: Sendable, Codable, Equatable {
        public struct ArtifactReference: Sendable, Codable, Equatable {
            public let kind: String
            public let path: String
            public let sha256Digest: String?

            public init(
                kind: String,
                path: String,
                sha256Digest: String? = nil
            ) {
                self.kind = kind
                self.path = path
                self.sha256Digest = sha256Digest
            }
        }

        public let evaluationHorizon: Int
        public let metrics: [String: Double]
        public let artifacts: [ArtifactReference]

        public init(
            evaluationHorizon: Int,
            metrics: [String: Double],
            artifacts: [ArtifactReference] = []
        ) {
            self.evaluationHorizon = evaluationHorizon
            self.metrics = metrics
            self.artifacts = artifacts
        }

        private enum CodingKeys: String, CodingKey {
            case evaluationHorizon
            case metrics
            case artifacts
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            evaluationHorizon = try container.decode(Int.self, forKey: .evaluationHorizon)
            metrics = try container.decode([String: Double].self, forKey: .metrics)
            artifacts = try container.decodeIfPresent(
                [ArtifactReference].self,
                forKey: .artifacts
            ) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(evaluationHorizon, forKey: .evaluationHorizon)
            try container.encode(metrics, forKey: .metrics)
            if !artifacts.isEmpty {
                try container.encode(artifacts, forKey: .artifacts)
            }
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
        public enum DigestAlgorithm: String, Sendable, Codable, Equatable {
            case legacyRootReplacementV1 = "sha256-root-replacement-v1"
            case relativePathV2 = "sha256-relative-path-v2"
        }

        public let path: String
        public let sha256Digest: String
        public let digestAlgorithm: DigestAlgorithm

        public init(
            path: String,
            sha256Digest: String,
            digestAlgorithm: DigestAlgorithm = .relativePathV2
        ) {
            self.path = path
            self.sha256Digest = sha256Digest
            self.digestAlgorithm = digestAlgorithm
        }

        private enum CodingKeys: String, CodingKey {
            case path
            case sha256Digest
            case digestAlgorithm
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decode(String.self, forKey: .path)
            sha256Digest = try container.decode(String.self, forKey: .sha256Digest)
            digestAlgorithm = try container.decodeIfPresent(
                DigestAlgorithm.self,
                forKey: .digestAlgorithm
            ) ?? .legacyRootReplacementV1
        }
    }

    /// Constraint statistic and dual state committed for this iteration.
    /// The metric identity is explicit because cost limits are meaningful only
    /// relative to their aggregation contract.
    public struct ConstraintState: Sendable, Codable, Equatable {
        public let metricID: String
        public let observedCost: Double
        public let costLimit: Double
        public let constraintGap: Double
        public let dualLambda: Double
        public let episodeCount: Int
        public let transitionCount: Int

        public init(
            metricID: String,
            observedCost: Double,
            costLimit: Double,
            constraintGap: Double,
            dualLambda: Double,
            episodeCount: Int,
            transitionCount: Int
        ) {
            self.metricID = metricID
            self.observedCost = observedCost
            self.costLimit = costLimit
            self.constraintGap = constraintGap
            self.dualLambda = dualLambda
            self.episodeCount = episodeCount
            self.transitionCount = transitionCount
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
    public let constraint: ConstraintState?
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
        constraint: ConstraintState? = nil,
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
        self.constraint = constraint
        self.checkpoint = checkpoint
    }
}
