import Testing

@testable import KuyuTraining

@Suite("Training evaluation pipeline contract")
struct TrainingEvaluationPipelineContractTests {
    @Test func acceptsIncreasingBoundedSearchStagesBeforeFullAcceptance() throws {
        let contract = TrainingEvaluationPipelineContract(
            searchFidelity: .screening(maximumControlStepsPerEpisode: 100),
            refinementPolicy: TrainingCandidateRefinementPolicy(
                evaluationFidelity: .screening(maximumControlStepsPerEpisode: 500)
            ),
            acceptanceFidelity: .fullScenario
        )

        try contract.validate()
    }

    @Test func rejectsRefinementThatDoesNotIncreaseSearchBudget() {
        let contract = TrainingEvaluationPipelineContract(
            searchFidelity: .screening(maximumControlStepsPerEpisode: 500),
            refinementPolicy: TrainingCandidateRefinementPolicy(
                evaluationFidelity: .screening(maximumControlStepsPerEpisode: 500)
            ),
            acceptanceFidelity: .fullScenario
        )

        #expect(
            throws: TrainingEvaluationPipelineContract.ValidationError
                .refinementMustIncreaseControlSteps(search: 500, refinement: 500)
        ) {
            try contract.validate()
        }
    }

    @Test func boundedRefinementStillRequiresFullAcceptance() {
        let contract = TrainingEvaluationPipelineContract(
            searchFidelity: .screening(maximumControlStepsPerEpisode: 100),
            refinementPolicy: TrainingCandidateRefinementPolicy(
                evaluationFidelity: .screening(maximumControlStepsPerEpisode: 500)
            ),
            acceptanceFidelity: .screening(maximumControlStepsPerEpisode: 1_000)
        )

        #expect(
            throws: TrainingEvaluationPipelineContract.ValidationError
                .acceptanceRequiresFullScenario
        ) {
            try contract.validate()
        }
    }
}
