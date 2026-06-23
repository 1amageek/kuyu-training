public enum AutonomousSafetyGateKind: String, Codable, Sendable, Equatable, CaseIterable {
    case modelBundleValidated
    case deterministicReplayValidated
    case scenarioRegressionPassed
    case stressRegressionPassed
    case safetyEnvelopeValidated
    case failSafeValidated
    case humanTakeoverValidated
    case telemetryComplete
    case artifactLineageComplete
    case hardwareBoundaryValidated
}
