import Foundation
import KuyuTrainingContracts
import Testing

@testable import KuyuEvolution

@Suite("Evolution parent selection policy")
struct EvolutionParentSelectionPolicyTests {
    @Test func qualityDiversitySelectsCellsAcrossAccumulatedGenerations() {
        let config = EvolutionRunConfig(
            runID: "qd-archive",
            taskID: "attitude",
            configHash: "config",
            policyID: "policy",
            populationSize: 3,
            generationCount: 3,
            eliteCount: 1,
            searchStrategy: .qualityDiversity,
            mutationRate: 0.1
        )
        let archived = fitness(
            candidateID: "g0-niche",
            generationIndex: 0,
            scalarFitness: 5,
            descriptor: ["taskPassRate": 0.5]
        )
        let current = fitness(
            candidateID: "g1-elite",
            generationIndex: 1,
            scalarFitness: 8,
            descriptor: ["taskPassRate": 1]
        )

        let selected = EvolutionParentSelectionPolicy().parentCandidateIDs(
            config: config,
            eliteCandidateIDs: [current.candidateID],
            generationFitness: [archived, current]
        )

        #expect(selected.first == current.candidateID)
        #expect(selected.contains(archived.candidateID))
    }

    private func fitness(
        candidateID: String,
        generationIndex: Int,
        scalarFitness: Double,
        descriptor: [String: Double]
    ) -> FitnessSummary {
        FitnessSummary(
            runID: "qd-archive",
            generationIndex: generationIndex,
            candidateID: candidateID,
            taskID: "attitude",
            scalarFitness: scalarFitness,
            rewardAverage: scalarFitness,
            taskPassRate: descriptor["taskPassRate"] ?? 0,
            safetyViolationRate: 0,
            behaviorDescriptor: descriptor
        )
    }
}
