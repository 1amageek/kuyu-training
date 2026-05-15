import Foundation

public enum LearningProjectCompletionGoalKind: String, Codable, Sendable, Equatable {
    case convergence
    case validationGate
}

public struct LearningProjectConvergenceGoal: Codable, Sendable, Equatable {
    public let kind: LearningProjectCompletionGoalKind
    public let targetTaskPassRate: Double
    public let targetHoldTimeRatio: Double?
    public let maximumSafetyViolationRate: Double
    public let minimumFitnessImprovement: Double
    public let minimumTaskPassRateImprovement: Double
    public let minimumHoldTimeRatioImprovement: Double
    public let patienceGenerations: Int
    public let maxGenerationBudget: Int

    public init(
        kind: LearningProjectCompletionGoalKind = .convergence,
        targetTaskPassRate: Double = 1,
        targetHoldTimeRatio: Double? = nil,
        maximumSafetyViolationRate: Double = 0,
        minimumFitnessImprovement: Double = 0.001,
        minimumTaskPassRateImprovement: Double = 0.001,
        minimumHoldTimeRatioImprovement: Double = 0.001,
        patienceGenerations: Int = 20,
        maxGenerationBudget: Int = 1_000
    ) {
        self.kind = kind
        self.targetTaskPassRate = targetTaskPassRate
        self.targetHoldTimeRatio = targetHoldTimeRatio
        self.maximumSafetyViolationRate = maximumSafetyViolationRate
        self.minimumFitnessImprovement = minimumFitnessImprovement
        self.minimumTaskPassRateImprovement = minimumTaskPassRateImprovement
        self.minimumHoldTimeRatioImprovement = minimumHoldTimeRatioImprovement
        self.patienceGenerations = max(1, patienceGenerations)
        self.maxGenerationBudget = max(1, maxGenerationBudget)
    }
}
