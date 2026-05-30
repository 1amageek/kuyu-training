import Foundation

/// Serializable snapshot of the mutable early-stopping state carried across
/// generations. The early-stopping configuration is reconstructed from
/// `EvolutionRunConfig`, so only the trajectory-dependent fields are persisted.
public struct EvolutionEarlyStoppingSnapshot: Sendable, Codable, Equatable {
    public var bestFitness: Double?
    public var bestTaskPassRate: Double?
    public var bestHoldTimeRatio: Double?
    public var stagnantGenerationCount: Int

    public init(
        bestFitness: Double? = nil,
        bestTaskPassRate: Double? = nil,
        bestHoldTimeRatio: Double? = nil,
        stagnantGenerationCount: Int = 0
    ) {
        self.bestFitness = bestFitness
        self.bestTaskPassRate = bestTaskPassRate
        self.bestHoldTimeRatio = bestHoldTimeRatio
        self.stagnantGenerationCount = stagnantGenerationCount
    }
}
