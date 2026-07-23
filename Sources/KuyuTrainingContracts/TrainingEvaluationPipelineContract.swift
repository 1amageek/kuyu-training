public struct TrainingEvaluationPipelineContract: Sendable, Equatable {
    public enum ValidationError: Error, Sendable, Equatable {
        case invalidSearchFidelity(TrainingEvaluationFidelity.ValidationError)
        case invalidRefinementPolicy(TrainingCandidateRefinementPolicy.ValidationError)
        case invalidAcceptanceFidelity(TrainingEvaluationFidelity.ValidationError)
        case screeningRequiresRefinement
        case fullScenarioProhibitsRefinement
        case refinementMustIncreaseControlSteps(search: Int, refinement: Int)
        case acceptanceRequiresFullScenario
    }

    public let searchFidelity: TrainingEvaluationFidelity
    public let refinementPolicy: TrainingCandidateRefinementPolicy?
    public let acceptanceFidelity: TrainingEvaluationFidelity

    public init(
        searchFidelity: TrainingEvaluationFidelity,
        refinementPolicy: TrainingCandidateRefinementPolicy?,
        acceptanceFidelity: TrainingEvaluationFidelity
    ) {
        self.searchFidelity = searchFidelity
        self.refinementPolicy = refinementPolicy
        self.acceptanceFidelity = acceptanceFidelity
    }

    public func validate() throws {
        do {
            try searchFidelity.validate()
        } catch let error as TrainingEvaluationFidelity.ValidationError {
            throw ValidationError.invalidSearchFidelity(error)
        }
        if let refinementPolicy {
            do {
                try refinementPolicy.validate()
            } catch let error as TrainingCandidateRefinementPolicy.ValidationError {
                throw ValidationError.invalidRefinementPolicy(error)
            }
        }
        do {
            try acceptanceFidelity.validate()
        } catch let error as TrainingEvaluationFidelity.ValidationError {
            throw ValidationError.invalidAcceptanceFidelity(error)
        }

        switch (searchFidelity, refinementPolicy) {
        case (.screening, nil):
            throw ValidationError.screeningRequiresRefinement
        case (.fullScenario, .some):
            throw ValidationError.fullScenarioProhibitsRefinement
        case let (.screening(searchMaximum), .some(refinementPolicy)):
            if case let .screening(refinementMaximum) = refinementPolicy.evaluationFidelity,
               refinementMaximum <= searchMaximum {
                throw ValidationError.refinementMustIncreaseControlSteps(
                    search: searchMaximum,
                    refinement: refinementMaximum
                )
            }
        case (.fullScenario, nil):
            break
        }
        guard acceptanceFidelity.isFullScenario else {
            throw ValidationError.acceptanceRequiresFullScenario
        }
    }
}
