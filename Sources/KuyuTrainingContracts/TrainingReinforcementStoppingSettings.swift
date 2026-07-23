public struct TrainingReinforcementStoppingSettings: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Sendable, Equatable {
        case invalidMinimumIterationCount(Int)
        case invalidPlateauWindow(Int)
        case invalidUnsafeWindow(Int)
    }

    public static let conservative = TrainingReinforcementStoppingSettings(
        minimumIterationCount: 3,
        plateauWindow: 3,
        unsafeWindow: 2,
        validated: ()
    )
    public static let singleIteration = TrainingReinforcementStoppingSettings(
        minimumIterationCount: 1,
        plateauWindow: 1,
        unsafeWindow: 2,
        validated: ()
    )
    public static let sustained = TrainingReinforcementStoppingSettings(
        minimumIterationCount: 4,
        plateauWindow: 6,
        unsafeWindow: 2,
        validated: ()
    )
    public static let convergence = TrainingReinforcementStoppingSettings(
        minimumIterationCount: 10,
        plateauWindow: 10,
        unsafeWindow: 2,
        validated: ()
    )
    public static let extendedConvergence = TrainingReinforcementStoppingSettings(
        minimumIterationCount: 20,
        plateauWindow: 20,
        unsafeWindow: 2,
        validated: ()
    )

    public let minimumIterationCount: Int
    public let plateauWindow: Int
    public let unsafeWindow: Int

    public init(
        minimumIterationCount: Int,
        plateauWindow: Int,
        unsafeWindow: Int
    ) throws {
        guard minimumIterationCount > 0 else {
            throw ValidationError.invalidMinimumIterationCount(minimumIterationCount)
        }
        guard plateauWindow > 0 else {
            throw ValidationError.invalidPlateauWindow(plateauWindow)
        }
        guard unsafeWindow > 0 else {
            throw ValidationError.invalidUnsafeWindow(unsafeWindow)
        }
        self.minimumIterationCount = minimumIterationCount
        self.plateauWindow = plateauWindow
        self.unsafeWindow = unsafeWindow
    }

    private init(
        minimumIterationCount: Int,
        plateauWindow: Int,
        unsafeWindow: Int,
        validated: Void
    ) {
        self.minimumIterationCount = minimumIterationCount
        self.plateauWindow = plateauWindow
        self.unsafeWindow = unsafeWindow
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            minimumIterationCount: container.decode(
                Int.self,
                forKey: .minimumIterationCount
            ),
            plateauWindow: container.decode(Int.self, forKey: .plateauWindow),
            unsafeWindow: container.decode(Int.self, forKey: .unsafeWindow)
        )
    }
}
