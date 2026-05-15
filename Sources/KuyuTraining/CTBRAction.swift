public struct CTBRAction: Sendable, Codable, Equatable {
    public let collectiveThrust: Double
    public let rollRate: Double
    public let pitchRate: Double
    public let yawRate: Double

    public init(
        collectiveThrust: Double,
        rollRate: Double,
        pitchRate: Double,
        yawRate: Double
    ) throws {
        let values = [collectiveThrust, rollRate, pitchRate, yawRate]
        guard values.allSatisfy(\.isFinite) else {
            throw CTBRActionError.nonFiniteValue
        }
        self.collectiveThrust = collectiveThrust
        self.rollRate = rollRate
        self.pitchRate = pitchRate
        self.yawRate = yawRate
    }

    public var values: [Double] {
        [collectiveThrust, rollRate, pitchRate, yawRate]
    }
}

public enum CTBRActionError: Error, Sendable, Equatable {
    case nonFiniteValue
}
