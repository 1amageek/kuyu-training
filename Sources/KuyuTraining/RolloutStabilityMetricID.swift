public struct RolloutStabilityMetricID: Sendable, Codable, Equatable, Hashable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public static let maximumAngularRate = RolloutStabilityMetricID(rawValue: "root.maximumAngularRate")
    public static let maximumAttitudeDeviation = RolloutStabilityMetricID(rawValue: "root.maximumAttitudeDeviation")
    public static let minimumRootAltitude = RolloutStabilityMetricID(rawValue: "root.minimumAltitude")
}
