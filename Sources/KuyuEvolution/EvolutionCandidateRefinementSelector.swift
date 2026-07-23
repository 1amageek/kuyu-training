import Foundation
import KuyuTrainingContracts

public struct EvolutionCandidateRefinementSelector: Sendable {
    public init() {}

    public func candidateIDs(
        candidates: [GenomeCandidate],
        screeningFitness: [FitnessSummary],
        eliteCount: Int,
        policy: TrainingCandidateRefinementPolicy
    ) -> [String] {
        let rankedCandidateIDs = rankedCandidateIDs(
            candidates: candidates,
            screeningFitness: screeningFitness
        )
        let count = policy.candidateCount(
            populationSize: candidates.count,
            eliteCount: eliteCount
        )
        var selected = Array(rankedCandidateIDs.prefix(count))
        if policy.retainsIncumbent {
            let protectedCandidateIDs = candidates.compactMap { candidate in
                candidate.isIncumbent == true || candidate.isCarryover == true
                    ? candidate.candidateID
                    : nil
            }
            for candidateID in protectedCandidateIDs where !selected.contains(candidateID) {
                selected.append(candidateID)
            }
        }
        return selected
    }

    public func rankedCandidateIDs(
        candidates: [GenomeCandidate],
        screeningFitness: [FitnessSummary]
    ) -> [String] {
        let candidateIDs = Set(candidates.map(\.candidateID))
        return screeningFitness
            .filter { summary in
                candidateIDs.contains(summary.candidateID)
                    && !summary.evaluationFidelity.isFullScenario
                    && summary.scalarFitness.isFinite
                    && summary.rewardAverage.isFinite
                    && summary.taskPassRate.isFinite
                    && summary.safetyViolationRate.isFinite
                    && summary.failureReasons.isEmpty
            }
            .sorted { lhs, rhs in
                if lhs.scalarFitness == rhs.scalarFitness {
                    return lhs.candidateID < rhs.candidateID
                }
                return lhs.scalarFitness > rhs.scalarFitness
            }
            .map(\.candidateID)
    }
}
