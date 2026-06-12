public enum RoArmM1ArmGripperSemantics {
    public static let driveIDs = [
        "baseYaw",
        "shoulderPitch",
        "elbowPitch",
        "wristPitch",
        "gripperClamp",
    ]

    public static let gripperDriveIndex = 4

    public static let actuatorSignalIDs = [
        "joint_1",
        "joint_2",
        "joint_3",
        "joint_4",
        "joint_5",
    ]

    public static var observationChannelNames: [String] {
        driveIDs.map { "\($0)Position" }
            + driveIDs.map { "\($0)Velocity" }
            + driveIDs.map { "\($0)TargetError" }
            + driveIDs.map { "\($0)LowerLimitMargin" }
            + driveIDs.map { "\($0)UpperLimitMargin" }
    }
}
