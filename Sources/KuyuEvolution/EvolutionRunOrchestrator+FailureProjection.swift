import Foundation
import KuyuTrainingContracts

extension EvolutionRunOrchestrator {
    func evaluationFailureFitness(
        config: EvolutionRunConfig,
        candidates: [GenomeCandidate],
        error: any Error
    ) -> [FitnessSummary] {
        let reason = "evaluation-failed:\(String(describing: error))"
        let failedMetric = -1.0e12
        return candidates.map { candidate in
            FitnessSummary(
                runID: config.runID,
                generationIndex: candidate.generationIndex,
                candidateID: candidate.candidateID,
                taskID: config.taskID,
                evaluationFidelity: config.searchEvaluationFidelity,
                scalarFitness: failedMetric,
                rewardAverage: failedMetric,
                taskPassRate: 0,
                safetyViolationRate: 1,
                holdTimeRatio: 0,
                altitudeErrorRatio: nil,
                energyPenalty: nil,
                noveltyScore: nil,
                teacherDelta: nil,
                workerThroughput: 0,
                behaviorDescriptor: [
                    "evaluation.failed": 1,
                ],
                failureReasons: [reason]
            )
        }
    }

    func evaluationFailureTraces(
        config: EvolutionRunConfig,
        candidates: [GenomeCandidate]
    ) -> [EvolutionCandidateEvaluationTrace] {
        let completedAt = Date()
        let requestedConcurrency = max(1, min(config.candidateEvaluationConcurrency, candidates.count))
        return candidates.enumerated().map { offset, candidate in
            EvolutionCandidateEvaluationTrace(
                runID: config.runID,
                generationIndex: candidate.generationIndex,
                candidateID: candidate.candidateID,
                requestedConcurrency: requestedConcurrency,
                activeEvaluationCountAtStart: min(offset + 1, requestedConcurrency),
                startedAt: completedAt,
                completedAt: completedAt
            )
        }
    }

    func evaluationCancellationFitness(
        config: EvolutionRunConfig,
        candidates: [GenomeCandidate]
    ) -> [FitnessSummary] {
        let cancelledMetric = -1.0e12
        return candidates.map { candidate in
            FitnessSummary(
                runID: config.runID,
                generationIndex: candidate.generationIndex,
                candidateID: candidate.candidateID,
                taskID: config.taskID,
                evaluationFidelity: config.searchEvaluationFidelity,
                scalarFitness: cancelledMetric,
                rewardAverage: cancelledMetric,
                taskPassRate: 0,
                safetyViolationRate: 1,
                holdTimeRatio: 0,
                altitudeErrorRatio: nil,
                energyPenalty: nil,
                noveltyScore: nil,
                teacherDelta: nil,
                workerThroughput: 0,
                behaviorDescriptor: [
                    "evaluation.cancelled": 1,
                ],
                failureReasons: ["evaluation-cancelled"]
            )
        }
    }

    func evaluationCancellationTraces(
        config: EvolutionRunConfig,
        candidates: [GenomeCandidate]
    ) -> [EvolutionCandidateEvaluationTrace] {
        let completedAt = Date()
        let requestedConcurrency = max(1, min(config.candidateEvaluationConcurrency, candidates.count))
        return candidates.map { candidate in
            EvolutionCandidateEvaluationTrace(
                runID: config.runID,
                generationIndex: candidate.generationIndex,
                candidateID: candidate.candidateID,
                requestedConcurrency: requestedConcurrency,
                activeEvaluationCountAtStart: 1,
                startedAt: completedAt,
                completedAt: completedAt
            )
        }
    }

    func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}
