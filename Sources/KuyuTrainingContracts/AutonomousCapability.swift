public enum AutonomousCapability: String, Codable, Sendable, Equatable, CaseIterable {
    case sensorIngestion
    case stateEstimation
    case dynamicsStabilization
    case trajectoryTracking
    case obstacleAvoidance
    case faultDetection
    case recoveryBehavior
    case missionExecution
    case safeStop
    case humanTakeover
}
