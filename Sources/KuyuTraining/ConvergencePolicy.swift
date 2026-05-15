public struct ConvergencePolicy: Sendable, Codable, Equatable {
    public let minimumImprovement: Double
    public let patienceGenerations: Int
    public let minimumTaskPassRate: Double
    public let minimumHoldTimeRatio: Double
    public let maximumAltitudeErrorRatio: Double?

    public init(
        minimumImprovement: Double,
        patienceGenerations: Int,
        minimumTaskPassRate: Double = 1,
        minimumHoldTimeRatio: Double = 1,
        maximumAltitudeErrorRatio: Double? = nil
    ) {
        self.minimumImprovement = max(0, minimumImprovement)
        self.patienceGenerations = max(1, patienceGenerations)
        self.minimumTaskPassRate = minimumTaskPassRate
        self.minimumHoldTimeRatio = minimumHoldTimeRatio
        self.maximumAltitudeErrorRatio = maximumAltitudeErrorRatio
    }
}
