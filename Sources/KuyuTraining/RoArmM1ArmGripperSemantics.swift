public enum RoArmM1ArmGripperSemantics {
    public static let driveIDs = [
        "baseYaw",
        "shoulderPitch",
        "elbowPitch",
        "wristPitch",
        "gripperClamp",
    ]

    public static let gripperDriveIndex = 4

    public static var observationChannelNames: [String] {
        driveIDs.map { "\($0)Position" }
            + driveIDs.map { "\($0)Velocity" }
            + driveIDs.map { "\($0)TargetError" }
            + driveIDs.map { "\($0)LowerLimitMargin" }
            + driveIDs.map { "\($0)UpperLimitMargin" }
    }
}
