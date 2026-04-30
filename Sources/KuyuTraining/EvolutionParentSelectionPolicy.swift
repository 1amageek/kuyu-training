import Foundation

public struct EvolutionParentSelectionPolicy: Sendable {
    public init() {}

    public func parentCandidateIDs(
        config: EvolutionRunConfig,
        eliteCandidateIDs: [String],
        generationFitness: [FitnessSummary]
    ) -> [String] {
        var selected: [String] = []
        appendUnique(eliteCandidateIDs, to: &selected)
        guard config.searchStrategy == .qualityDiversity else {
            return selected
        }
        let qdArchive = EvolutionQualityDiversityArchiveBuilder()
            .build(runID: config.runID, fitness: generationFitness)
        let qdCandidateIDs = qdArchive.cells
            .sorted { lhs, rhs in
                if lhs.fitness == rhs.fitness {
                    return lhs.candidateID < rhs.candidateID
                }
                return lhs.fitness > rhs.fitness
            }
            .map(\.candidateID)
        appendUnique(qdCandidateIDs, to: &selected)
        return selected
    }

    private func appendUnique(_ candidates: [String], to selected: inout [String]) {
        for candidate in candidates where !selected.contains(candidate) {
            selected.append(candidate)
        }
    }
}
