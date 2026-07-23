import Foundation
import KuyuTrainingContracts

extension EvolutionRunArtifactValidator {
    func validateEvaluationTraces(
        _ traces: [EvolutionCandidateEvaluationTrace],
        manifest: EvolutionRunManifest,
        candidateIDs: Set<String>
    ) throws {
        var seen = Set<String>()
        for trace in traces {
            guard candidateIDs.contains(trace.candidateID) else {
                throw ValidationError.missingEvaluationTrace(trace.candidateID)
            }
            guard seen.insert(trace.candidateID).inserted else {
                throw ValidationError.duplicateEvaluationTrace(trace.candidateID)
            }
            guard trace.requestedConcurrency >= 1,
                  trace.requestedConcurrency <= manifest.candidateEvaluationConcurrency,
                  trace.activeEvaluationCountAtStart >= 1,
                  trace.activeEvaluationCountAtStart <= trace.requestedConcurrency,
                  trace.durationSeconds.isFinite,
                  trace.durationSeconds >= 0,
                  trace.completedAt >= trace.startedAt else {
                throw ValidationError.invalidEvaluationTrace(trace.candidateID)
            }
        }
        for candidateID in candidateIDs where !seen.contains(candidateID) {
            throw ValidationError.missingEvaluationTrace(candidateID)
        }
    }
}
