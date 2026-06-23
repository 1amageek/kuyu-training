import KuyuTrainingContracts
public enum RolloutTerminalReason {
    public static let curriculumHorizon = "curriculum-horizon"
    public static let timeLimit = "time-limit"

    public static func isHorizonLimit(_ terminalReason: String?) -> Bool {
        terminalReason == curriculumHorizon || terminalReason == timeLimit
    }

    public static func isBootstrapableTruncation(_ terminalReason: String?) -> Bool {
        isHorizonLimit(terminalReason)
    }
}
