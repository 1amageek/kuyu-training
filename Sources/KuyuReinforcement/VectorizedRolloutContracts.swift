import Foundation
import KuyuScenarios
import KuyuTrainingContracts

public struct VectorizedCandidateReference<Candidate: Sendable>: Sendable {
    public let candidateID: String
    public let candidate: Candidate

    public init(candidateID: String, candidate: Candidate) {
        self.candidateID = candidateID
        self.candidate = candidate
    }
}

public struct VectorizedRolloutRequest<Candidate: Sendable>: Sendable {
    public let batchSpec: VectorizedTrainingBatchSpec
    public let candidates: [VectorizedCandidateReference<Candidate>]
    public let artifactDirectory: URL
    public let randomSeed: UInt64

    public init(
        batchSpec: VectorizedTrainingBatchSpec,
        candidates: [VectorizedCandidateReference<Candidate>],
        artifactDirectory: URL,
        randomSeed: UInt64
    ) throws {
        guard candidates.count == batchSpec.populationSize else {
            throw VectorizedRolloutRequestError.populationCountMismatch(
                expected: batchSpec.populationSize,
                actual: candidates.count
            )
        }
        var seen: Set<String> = []
        for candidate in candidates {
            guard !candidate.candidateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VectorizedRolloutRequestError.emptyCandidateID
            }
            guard seen.insert(candidate.candidateID).inserted else {
                throw VectorizedRolloutRequestError.duplicateCandidateID(candidate.candidateID)
            }
        }
        self.batchSpec = batchSpec
        self.candidates = candidates
        self.artifactDirectory = artifactDirectory
        self.randomSeed = randomSeed
    }
}

public enum VectorizedRolloutRequestError: Error, Sendable, Equatable {
    case populationCountMismatch(expected: Int, actual: Int)
    case emptyCandidateID
    case duplicateCandidateID(String)
}

public struct VectorizedCandidateRolloutSummary: Sendable, Codable, Equatable {
    public let candidateID: String
    public let rewardAverage: Double
    public let fitness: Double
    public let taskPassRate: Double
    public let safetyViolationRate: Double
    public let rolloutCount: Int
    public let taskQuality: [ReferenceQuadrotorTaskQualitySummary]

    public init(
        candidateID: String,
        rewardAverage: Double,
        fitness: Double,
        taskPassRate: Double,
        safetyViolationRate: Double,
        rolloutCount: Int,
        taskQuality: [ReferenceQuadrotorTaskQualitySummary] = []
    ) throws {
        guard !candidateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VectorizedCandidateRolloutSummaryError.emptyCandidateID
        }
        guard rewardAverage.isFinite, fitness.isFinite, taskPassRate.isFinite, safetyViolationRate.isFinite else {
            throw VectorizedCandidateRolloutSummaryError.nonFiniteMetric
        }
        guard taskPassRate >= 0, taskPassRate <= 1 else {
            throw VectorizedCandidateRolloutSummaryError.invalidTaskPassRate
        }
        guard safetyViolationRate >= 0, safetyViolationRate <= 1 else {
            throw VectorizedCandidateRolloutSummaryError.invalidSafetyViolationRate
        }
        guard rolloutCount > 0 else {
            throw VectorizedCandidateRolloutSummaryError.nonPositiveRolloutCount
        }
        self.candidateID = candidateID
        self.rewardAverage = rewardAverage
        self.fitness = fitness
        self.taskPassRate = taskPassRate
        self.safetyViolationRate = safetyViolationRate
        self.rolloutCount = rolloutCount
        self.taskQuality = taskQuality
    }
}

public enum VectorizedCandidateRolloutSummaryError: Error, Sendable, Equatable {
    case emptyCandidateID
    case nonFiniteMetric
    case invalidTaskPassRate
    case invalidSafetyViolationRate
    case nonPositiveRolloutCount
}

public struct VectorizedRolloutBatchResult: Sendable, Codable, Equatable {
    public let batchSpec: VectorizedTrainingBatchSpec
    public let summaries: [VectorizedCandidateRolloutSummary]
    public let artifactDirectory: URL
    public let elapsedSeconds: Double

    public init(
        batchSpec: VectorizedTrainingBatchSpec,
        summaries: [VectorizedCandidateRolloutSummary],
        artifactDirectory: URL,
        elapsedSeconds: Double
    ) throws {
        guard summaries.count == batchSpec.populationSize else {
            throw VectorizedRolloutBatchResultError.summaryCountMismatch(
                expected: batchSpec.populationSize,
                actual: summaries.count
            )
        }
        guard elapsedSeconds.isFinite, elapsedSeconds >= 0 else {
            throw VectorizedRolloutBatchResultError.invalidElapsedSeconds
        }
        self.batchSpec = batchSpec
        self.summaries = summaries
        self.artifactDirectory = artifactDirectory
        self.elapsedSeconds = elapsedSeconds
    }
}

public enum VectorizedRolloutBatchResultError: Error, Sendable, Equatable {
    case summaryCountMismatch(expected: Int, actual: Int)
    case invalidElapsedSeconds
}
