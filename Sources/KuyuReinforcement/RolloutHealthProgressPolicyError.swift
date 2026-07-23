public enum RolloutHealthProgressPolicyError: Error, Sendable, Equatable {
    case invalidMinimumEpisodeCount(Int)
    case invalidRewardAverageImprovement(Double)
    case invalidStabilityToleranceScale(Double)
    case invalidSafetyCostImprovementFraction(Double)
}
