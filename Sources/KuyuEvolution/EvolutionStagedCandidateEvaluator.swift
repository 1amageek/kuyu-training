import Foundation
import KuyuTrainingContracts

public struct EvolutionStagedCandidateEvaluator: EvolutionPopulationBatchEvaluating {
    public enum EvaluationError: Error, Sendable, Equatable {
        case missingRefinementPolicy
        case refinementPolicyMismatch
        case invalidSummaryCount(stage: TrainingWorkPhase, expected: Int, actual: Int)
        case missingSummary(stage: TrainingWorkPhase, candidateID: String)
    }

    let screeningEvaluator: any EvolutionCandidateBatchEvaluating
    let refinementEvaluator: any EvolutionCandidateBatchEvaluating
    let refinementPolicy: TrainingCandidateRefinementPolicy
    let refinementGatePolicy: EvolutionGatePolicy
    let selector: EvolutionCandidateRefinementSelector

    public init(
        screeningEvaluator: any EvolutionCandidateBatchEvaluating,
        refinementEvaluator: any EvolutionCandidateBatchEvaluating,
        refinementPolicy: TrainingCandidateRefinementPolicy,
        refinementGatePolicy: EvolutionGatePolicy,
        selector: EvolutionCandidateRefinementSelector = EvolutionCandidateRefinementSelector()
    ) {
        self.screeningEvaluator = screeningEvaluator
        self.refinementEvaluator = refinementEvaluator
        self.refinementPolicy = refinementPolicy
        self.refinementGatePolicy = refinementGatePolicy
        self.selector = selector
    }

    public func evaluateCandidate(
        request: EvolutionCandidateEvaluationRequest
    ) async throws -> FitnessSummary {
        let summaries = try await evaluateCandidates(request: EvolutionCandidateBatchEvaluationRequest(
            config: request.config,
            candidates: [request.candidate],
            generationArtifactDirectory: request.generationArtifactDirectory,
            workerCount: request.workerCount
        ))
        guard let summary = summaries.first else {
            throw EvaluationError.missingSummary(
                stage: .refinement,
                candidateID: request.candidate.candidateID
            )
        }
        return summary
    }

    public func evaluateCandidates(
        request: EvolutionCandidateBatchEvaluationRequest
    ) async throws -> [FitnessSummary] {
        try await evaluateCandidates(request: request, progressReporter: nil)
    }

    public func evaluateCandidates(
        request: EvolutionCandidateBatchEvaluationRequest,
        progressReporter: (any TrainingProgressReporting)?
    ) async throws -> [FitnessSummary] {
        guard let configuredPolicy = request.config.searchRefinementPolicy else {
            throw EvaluationError.missingRefinementPolicy
        }
        guard configuredPolicy == refinementPolicy else {
            throw EvaluationError.refinementPolicyMismatch
        }
        try refinementPolicy.validate()

        let screeningRequest = try stageRequest(
            request,
            candidates: request.candidates,
            phase: .screening
        )
        let screening = try await screeningEvaluator.evaluateCandidates(
            request: screeningRequest,
            progressReporter: progressReporter
        )
        try validate(
            screening,
            candidates: request.candidates,
            stage: .screening
        )

        let refinementByID = try await refinementFitness(
            request: request,
            screeningFitness: screening,
            progressReporter: progressReporter
        )
        let screeningByID = Dictionary(uniqueKeysWithValues: screening.map { ($0.candidateID, $0) })
        return try request.candidates.map { candidate in
            guard let screeningSummary = screeningByID[candidate.candidateID] else {
                throw EvaluationError.missingSummary(
                    stage: .screening,
                    candidateID: candidate.candidateID
                )
            }
            guard let refinedSummary = refinementByID[candidate.candidateID] else {
                return projectedScreeningSummary(screeningSummary, selected: false)
            }
            return projectedRefinementSummary(
                refinedSummary,
                screeningSummary: screeningSummary
            )
        }
    }
}
