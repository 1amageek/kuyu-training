public enum EvolutionSearchStrategy: String, Sendable, Codable, Equatable {
    case genetic
    case antitheticEvolutionStrategy
    case qualityDiversity

    public var contractVersion: Int {
        switch self {
        case .genetic:
            1
        case .antitheticEvolutionStrategy, .qualityDiversity:
            2
        }
    }
}
