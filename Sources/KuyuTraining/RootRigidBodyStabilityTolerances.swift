public struct RootRigidBodyStabilityTolerances: Sendable, Codable, Equatable {
    public let maxAngularRateAbsoluteTolerance: Double
    public let maxAngularRateRelativeTolerance: Double
    public let maxAttitudeDeviationAbsoluteTolerance: Double
    public let maxAttitudeDeviationRelativeTolerance: Double
    public let minRootAltitudeTolerance: Double

    public static let conservative = RootRigidBodyStabilityTolerances(
        uncheckedMaxAngularRateAbsoluteTolerance: 0.25,
        uncheckedMaxAngularRateRelativeTolerance: 0.10,
        uncheckedMaxAttitudeDeviationAbsoluteTolerance: 0.05,
        uncheckedMaxAttitudeDeviationRelativeTolerance: 0.10,
        uncheckedMinRootAltitudeTolerance: 0.05
    )

    public init(
        maxAngularRateAbsoluteTolerance: Double = 0.25,
        maxAngularRateRelativeTolerance: Double = 0.10,
        maxAttitudeDeviationAbsoluteTolerance: Double = 0.05,
        maxAttitudeDeviationRelativeTolerance: Double = 0.10,
        minRootAltitudeTolerance: Double = 0.05
    ) throws {
        guard maxAngularRateAbsoluteTolerance.isFinite,
              maxAngularRateAbsoluteTolerance >= 0,
              maxAngularRateRelativeTolerance.isFinite,
              maxAngularRateRelativeTolerance >= 0,
              maxAttitudeDeviationAbsoluteTolerance.isFinite,
              maxAttitudeDeviationAbsoluteTolerance >= 0,
              maxAttitudeDeviationRelativeTolerance.isFinite,
              maxAttitudeDeviationRelativeTolerance >= 0,
              minRootAltitudeTolerance.isFinite,
              minRootAltitudeTolerance >= 0 else {
            throw RolloutHealthAcceptancePolicyError.invalidTolerance
        }
        self.maxAngularRateAbsoluteTolerance = maxAngularRateAbsoluteTolerance
        self.maxAngularRateRelativeTolerance = maxAngularRateRelativeTolerance
        self.maxAttitudeDeviationAbsoluteTolerance = maxAttitudeDeviationAbsoluteTolerance
        self.maxAttitudeDeviationRelativeTolerance = maxAttitudeDeviationRelativeTolerance
        self.minRootAltitudeTolerance = minRootAltitudeTolerance
    }

    public func scaled(
        angularRateAbsoluteMultiplier: Double = 1,
        angularRateRelativeMultiplier: Double = 1,
        attitudeAbsoluteMultiplier: Double = 1,
        attitudeRelativeMultiplier: Double = 1,
        altitudeMultiplier: Double = 1
    ) throws -> RootRigidBodyStabilityTolerances {
        try RootRigidBodyStabilityTolerances(
            maxAngularRateAbsoluteTolerance: maxAngularRateAbsoluteTolerance
                * angularRateAbsoluteMultiplier,
            maxAngularRateRelativeTolerance: maxAngularRateRelativeTolerance
                * angularRateRelativeMultiplier,
            maxAttitudeDeviationAbsoluteTolerance: maxAttitudeDeviationAbsoluteTolerance
                * attitudeAbsoluteMultiplier,
            maxAttitudeDeviationRelativeTolerance: maxAttitudeDeviationRelativeTolerance
                * attitudeRelativeMultiplier,
            minRootAltitudeTolerance: minRootAltitudeTolerance * altitudeMultiplier
        )
    }

    private init(
        uncheckedMaxAngularRateAbsoluteTolerance: Double,
        uncheckedMaxAngularRateRelativeTolerance: Double,
        uncheckedMaxAttitudeDeviationAbsoluteTolerance: Double,
        uncheckedMaxAttitudeDeviationRelativeTolerance: Double,
        uncheckedMinRootAltitudeTolerance: Double
    ) {
        maxAngularRateAbsoluteTolerance = uncheckedMaxAngularRateAbsoluteTolerance
        maxAngularRateRelativeTolerance = uncheckedMaxAngularRateRelativeTolerance
        maxAttitudeDeviationAbsoluteTolerance = uncheckedMaxAttitudeDeviationAbsoluteTolerance
        maxAttitudeDeviationRelativeTolerance = uncheckedMaxAttitudeDeviationRelativeTolerance
        minRootAltitudeTolerance = uncheckedMinRootAltitudeTolerance
    }
}
