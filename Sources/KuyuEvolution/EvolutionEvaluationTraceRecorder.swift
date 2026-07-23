import Foundation
import KuyuTrainingContracts

actor EvolutionEvaluationTraceRecorder {
    private var activeCount = 0

    func begin() -> (startedAt: Date, activeEvaluationCountAtStart: Int) {
        activeCount += 1
        return (Date(), activeCount)
    }

    func end(
        runID: String,
        generationIndex: Int,
        candidateID: String,
        requestedConcurrency: Int,
        started: (startedAt: Date, activeEvaluationCountAtStart: Int)
    ) -> EvolutionCandidateEvaluationTrace {
        let completedAt = Date()
        activeCount = max(0, activeCount - 1)
        return EvolutionCandidateEvaluationTrace(
            runID: runID,
            generationIndex: generationIndex,
            candidateID: candidateID,
            requestedConcurrency: requestedConcurrency,
            activeEvaluationCountAtStart: started.activeEvaluationCountAtStart,
            startedAt: started.startedAt,
            completedAt: completedAt
        )
    }
}
