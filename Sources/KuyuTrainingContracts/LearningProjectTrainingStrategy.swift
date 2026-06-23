import Foundation

public enum LearningProjectTrainingStrategyKind: String, Codable, Sendable, Equatable, CaseIterable {
    case supervised
    case imitation
    case reinforcementLearning
    case genetic
    case hybrid
    case worldModel
}

public struct LearningProjectTrainingStrategy: Codable, Sendable, Equatable {
    public let kind: LearningProjectTrainingStrategyKind
    public let evolutionSearchStrategy: EvolutionSearchStrategy?
    public let bootstrapSource: EvolutionBootstrapSource
    public let worldModelUsage: EvolutionWorldModelUsage
    public let usesQualityGate: Bool
    public let usesReinforcementFineTuning: Bool

    public init(
        kind: LearningProjectTrainingStrategyKind,
        evolutionSearchStrategy: EvolutionSearchStrategy?,
        bootstrapSource: EvolutionBootstrapSource,
        worldModelUsage: EvolutionWorldModelUsage,
        usesQualityGate: Bool,
        usesReinforcementFineTuning: Bool
    ) {
        self.kind = kind
        self.evolutionSearchStrategy = evolutionSearchStrategy
        self.bootstrapSource = bootstrapSource
        self.worldModelUsage = worldModelUsage
        self.usesQualityGate = usesQualityGate
        self.usesReinforcementFineTuning = usesReinforcementFineTuning
    }
}
