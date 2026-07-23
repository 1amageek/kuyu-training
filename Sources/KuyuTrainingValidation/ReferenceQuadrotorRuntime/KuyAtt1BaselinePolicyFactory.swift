import KuyuPhysics
import KuyuScenarios

public struct KuyAtt1BaselinePolicyFactory: ReferenceQuadrotorPolicyFactory {
    public let policyID: String
    public let parameters: ReferenceQuadrotorParameters
    public let gains: ImuRateDampingCutGains
    public let mode: KuyAtt1BaselineMode
    public let teacherConfig: PrivilegedAltitudeHoldTeacherConfig

    public init(
        parameters: ReferenceQuadrotorParameters = .baseline,
        gains: ImuRateDampingCutGains,
        mode: KuyAtt1BaselineMode,
        teacherConfig: PrivilegedAltitudeHoldTeacherConfig = .activeAltitudeHold
    ) {
        self.parameters = parameters
        self.gains = gains
        self.mode = mode
        self.teacherConfig = teacherConfig
        switch mode {
        case .teacher:
            self.policyID = "teacherActiveAltitudeHold"
        case .sensor:
            self.policyID = "sensorBaseline"
        }
    }

    public func makePolicy(
        definition: ReferenceQuadrotorScenarioDefinition,
        workerIndex: Int
    ) throws -> any ReferenceQuadrotorEnvironmentPolicy {
        switch definition.kind {
        case .liftHover, .singleLiftHover:
            return try KuyLiftBaselineEnvironmentPolicy(
                definition: definition,
                parameters: parameters,
                mode: mode,
                hoverThrustScale: gains.hoverThrustScale
            )
        case .hoverStart, .impulseTorqueShock, .sustainedWindTorque, .sensorDriftStress, .actuatorDegradation:
            return try KuyAtt1BaselineEnvironmentPolicy(
                definition: definition,
                parameters: parameters,
                gains: gains,
                mode: mode,
                teacherConfig: teacherConfig
            )
        }
    }
}
