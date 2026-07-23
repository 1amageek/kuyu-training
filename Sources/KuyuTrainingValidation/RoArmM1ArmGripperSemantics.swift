import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
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

    public static let jointScalarIDs = [
        "base_to_L1",
        "L1_to_L2",
        "L2_to_L3",
        "L3_to_L4",
        "L4_to_L5_1_A",
    ]

    public static var jointScalarIDCandidates: [[String]] {
        zip(jointScalarIDs, zip(driveIDs, actuatorSignalIDs)).map { primary, aliases in
            [primary, aliases.0, aliases.1]
        }
    }

    public static var observationChannelNames: [String] {
        driveIDs.map { "\($0)Position" }
            + driveIDs.map { "\($0)Velocity" }
            + driveIDs.map { "\($0)TargetError" }
            + driveIDs.map { "\($0)LowerLimitMargin" }
            + driveIDs.map { "\($0)UpperLimitMargin" }
    }
}
