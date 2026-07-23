import KuyuTrainingContracts

extension EvolutionStagedCandidateEvaluator {
    func stageRequest(
        _ request: EvolutionCandidateBatchEvaluationRequest,
        candidates: [GenomeCandidate],
        phase: TrainingWorkPhase
    ) throws -> EvolutionCandidateBatchEvaluationRequest {
        try EvolutionCandidateBatchEvaluationRequest(
            config: request.config,
            candidates: candidates,
            generationArtifactDirectory: request.generationArtifactDirectory,
            workerCount: request.workerCount,
            batchIndex: 0,
            batchCount: 1,
            populationSize: request.populationSize,
            workPhase: phase
        )
    }

    func validate(
        _ summaries: [FitnessSummary],
        candidates: [GenomeCandidate],
        stage: TrainingWorkPhase
    ) throws {
        guard summaries.count == candidates.count else {
            throw EvaluationError.invalidSummaryCount(
                stage: stage,
                expected: candidates.count,
                actual: summaries.count
            )
        }
        let summaryIDs = Set(summaries.map(\.candidateID))
        for candidate in candidates where !summaryIDs.contains(candidate.candidateID) {
            throw EvaluationError.missingSummary(stage: stage, candidateID: candidate.candidateID)
        }
    }

    func projectedScreeningSummary(
        _ summary: FitnessSummary,
        selected: Bool
    ) -> FitnessSummary {
        var descriptor = summary.behaviorDescriptor
        descriptor["search.refinementSelected"] = selected ? 1 : 0
        return copy(
            summary,
            behaviorDescriptor: descriptor,
            failureReasons: summary.failureReasons + ["search-refinement-not-selected"]
        )
    }

    func projectedRefinementSummary(
        _ summary: FitnessSummary,
        screeningSummary: FitnessSummary
    ) -> FitnessSummary {
        var descriptor = summary.behaviorDescriptor
        descriptor["search.refinementSelected"] = 1
        if screeningSummary.scalarFitness.isFinite {
            descriptor["search.screeningFitness"] = screeningSummary.scalarFitness
        }
        return copy(
            summary,
            behaviorDescriptor: descriptor,
            failureReasons: summary.failureReasons
        )
    }

    private func copy(
        _ summary: FitnessSummary,
        behaviorDescriptor: [String: Double],
        failureReasons: [String]
    ) -> FitnessSummary {
        FitnessSummary(
            runID: summary.runID,
            generationIndex: summary.generationIndex,
            candidateID: summary.candidateID,
            taskID: summary.taskID,
            evaluationFidelity: summary.evaluationFidelity,
            scalarFitness: summary.scalarFitness,
            rewardAverage: summary.rewardAverage,
            taskPassRate: summary.taskPassRate,
            safetyViolationRate: summary.safetyViolationRate,
            holdTimeRatio: summary.holdTimeRatio,
            altitudeErrorRatio: summary.altitudeErrorRatio,
            energyPenalty: summary.energyPenalty,
            noveltyScore: summary.noveltyScore,
            teacherDelta: summary.teacherDelta,
            workerThroughput: summary.workerThroughput,
            behaviorDescriptor: behaviorDescriptor,
            failureReasons: failureReasons
        )
    }
}
