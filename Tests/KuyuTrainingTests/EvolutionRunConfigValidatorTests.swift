import KuyuEvolution
import KuyuTrainingContracts
import Testing

@Suite("Evolution run config validator")
struct EvolutionRunConfigValidatorTests {
    @Test func rejectsPopulationWithoutVariationCandidates() {
        let config = makeConfig(populationSize: 1, generationCount: 2)

        #expect(throws: EvolutionRunConfigValidator.ValidationError.self) {
            try EvolutionRunConfigValidator().validate(config)
        }
    }

    @Test func rejectsIncompleteAntitheticPairs() {
        let config = makeConfig(
            populationSize: 4,
            generationCount: 2,
            searchStrategy: .antitheticEvolutionStrategy
        )

        #expect(throws: EvolutionRunConfigValidator.ValidationError.self) {
            try EvolutionRunConfigValidator().validate(config)
        }
    }

    @Test func rejectsMutationRatesOutsideProbabilityDomain() {
        let config = makeConfig(populationSize: 2, generationCount: 2, mutationRate: 1.01)

        #expect(throws: EvolutionRunConfigValidator.ValidationError.self) {
            try EvolutionRunConfigValidator().validate(config)
        }
    }

    @Test func acceptsSingleCandidateEvaluationWithoutEvolution() throws {
        let config = makeConfig(populationSize: 1, generationCount: 1, mutationRate: 0)

        try EvolutionRunConfigValidator().validate(config)
    }

    @Test func rejectsBoundedRefinementFidelity() {
        let config = makeConfig(
            populationSize: 2,
            generationCount: 2,
            searchEvaluationFidelity: .screening(maximumControlStepsPerEpisode: 1_000),
            searchRefinementPolicy: TrainingCandidateRefinementPolicy(
                evaluationFidelity: .screening(maximumControlStepsPerEpisode: 5_000)
            )
        )

        #expect(
            throws: EvolutionRunConfigValidator.ValidationError
                .unsupportedBoundedRefinementFidelity(
                    .screening(maximumControlStepsPerEpisode: 5_000)
                )
        ) {
            try EvolutionRunConfigValidator().validate(config)
        }
    }

    @Test func acceptsFullScenarioRefinementFidelity() throws {
        let config = makeConfig(
            populationSize: 2,
            generationCount: 2,
            searchEvaluationFidelity: .screening(maximumControlStepsPerEpisode: 1_000),
            searchRefinementPolicy: TrainingCandidateRefinementPolicy(
                evaluationFidelity: .fullScenario
            )
        )

        try EvolutionRunConfigValidator().validate(config)
    }

    private func makeConfig(
        populationSize: Int,
        generationCount: Int,
        searchStrategy: EvolutionSearchStrategy = .genetic,
        mutationRate: Double = 0.1,
        searchEvaluationFidelity: TrainingEvaluationFidelity = .fullScenario,
        searchRefinementPolicy: TrainingCandidateRefinementPolicy? = nil
    ) -> EvolutionRunConfig {
        EvolutionRunConfig(
            runID: "validation",
            taskID: "attitude",
            configHash: "config",
            policyID: "policy",
            populationSize: populationSize,
            generationCount: generationCount,
            eliteCount: 1,
            searchEvaluationFidelity: searchEvaluationFidelity,
            searchRefinementPolicy: searchRefinementPolicy,
            searchStrategy: searchStrategy,
            mutationRate: mutationRate
        )
    }
}
