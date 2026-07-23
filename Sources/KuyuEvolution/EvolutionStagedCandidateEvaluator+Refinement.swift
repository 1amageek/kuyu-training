import KuyuTrainingContracts

extension EvolutionStagedCandidateEvaluator {
    func refinementFitness(
        request: EvolutionCandidateBatchEvaluationRequest,
        screeningFitness: [FitnessSummary],
        progressReporter: (any TrainingProgressReporting)?
    ) async throws -> [String: FitnessSummary] {
        let initialIDs = selector.candidateIDs(
            candidates: request.candidates,
            screeningFitness: screeningFitness,
            eliteCount: request.config.eliteCount,
            policy: refinementPolicy
        )
        var refinementByID = try await evaluateRefinement(
            request: request,
            candidateIDs: Set(initialIDs),
            phase: .refinement,
            progressReporter: progressReporter
        )
        let targetCount = refinementPolicy.candidateCount(
            populationSize: request.candidates.count,
            eliteCount: request.config.eliteCount
        )
        let passingCount = refinementByID.values.filter(
            refinementGatePolicy.candidatePassesRefinement
        ).count
        guard passingCount < targetCount else {
            return refinementByID
        }

        let rankedIDs = selector.rankedCandidateIDs(
            candidates: request.candidates,
            screeningFitness: screeningFitness
        )
        let remainingIDs = Set(rankedIDs.filter { refinementByID[$0] == nil })
        let backfill = try await evaluateRefinement(
            request: request,
            candidateIDs: remainingIDs,
            phase: .refinementBackfill,
            progressReporter: progressReporter
        )
        refinementByID.merge(backfill) { _, replacement in replacement }
        return refinementByID
    }

    private func evaluateRefinement(
        request: EvolutionCandidateBatchEvaluationRequest,
        candidateIDs: Set<String>,
        phase: TrainingWorkPhase,
        progressReporter: (any TrainingProgressReporting)?
    ) async throws -> [String: FitnessSummary] {
        let candidates = request.candidates.filter { candidateIDs.contains($0.candidateID) }
        guard !candidates.isEmpty else { return [:] }
        let stageRequest = try stageRequest(request, candidates: candidates, phase: phase)
        let summaries = try await refinementEvaluator.evaluateCandidates(
            request: stageRequest,
            progressReporter: progressReporter
        )
        try validate(summaries, candidates: candidates, stage: phase)
        return Dictionary(uniqueKeysWithValues: summaries.map { ($0.candidateID, $0) })
    }
}
