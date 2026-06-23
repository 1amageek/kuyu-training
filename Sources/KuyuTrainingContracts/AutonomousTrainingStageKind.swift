public enum AutonomousTrainingStageKind: String, Codable, Sendable, Equatable, CaseIterable {
    case imitation
    case supervised
    case reinforcement
    case evolution
    case worldModel
    case stress
    case regression
    case hardwareInTheLoop
    case closedCourse
    case deploymentShadow
}
