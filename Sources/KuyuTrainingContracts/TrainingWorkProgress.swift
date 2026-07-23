import Foundation

public struct TrainingWorkProgress: Codable, Sendable, Hashable {
    public let scope: TrainingWorkScope
    public let phase: TrainingWorkPhase
    public let state: TrainingWorkState
    public let unit: TrainingWorkUnit
    public let completedUnitCount: Int
    public let totalUnitCount: Int
    public let populationSize: Int?
    public let timestamp: Date

    private enum CodingKeys: String, CodingKey {
        case scope
        case phase
        case state
        case unit
        case completedUnitCount
        case totalUnitCount
        case populationSize
        case timestamp
    }

    public var fractionCompleted: Double {
        Double(completedUnitCount) / Double(totalUnitCount)
    }

    public init(
        scope: TrainingWorkScope,
        phase: TrainingWorkPhase,
        state: TrainingWorkState,
        unit: TrainingWorkUnit,
        completedUnitCount: Int,
        totalUnitCount: Int,
        populationSize: Int? = nil,
        timestamp: Date = Date()
    ) throws {
        guard totalUnitCount > 0,
              completedUnitCount >= 0,
              completedUnitCount <= totalUnitCount else {
            throw TrainingWorkContractError.invalidUnitCount(
                completed: completedUnitCount,
                total: totalUnitCount
            )
        }
        if let populationSize, populationSize <= 0 {
            throw TrainingWorkContractError.invalidPopulationSize(populationSize)
        }
        self.scope = scope
        self.phase = phase
        self.state = state
        self.unit = unit
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.populationSize = populationSize
        self.timestamp = timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            scope: container.decode(TrainingWorkScope.self, forKey: .scope),
            phase: container.decode(TrainingWorkPhase.self, forKey: .phase),
            state: container.decode(TrainingWorkState.self, forKey: .state),
            unit: container.decode(TrainingWorkUnit.self, forKey: .unit),
            completedUnitCount: container.decode(Int.self, forKey: .completedUnitCount),
            totalUnitCount: container.decode(Int.self, forKey: .totalUnitCount),
            populationSize: container.decodeIfPresent(Int.self, forKey: .populationSize),
            timestamp: container.decode(Date.self, forKey: .timestamp)
        )
    }
}
