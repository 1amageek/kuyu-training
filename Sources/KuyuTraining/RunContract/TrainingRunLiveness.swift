/// Liveness derived from `outcome.json` + heartbeat process check.
///
/// Derivation (normative):
/// - terminal status → `finished`
/// - `paused` → `paused(processAlive:)`
/// - `running` + writer process alive → `live`
/// - `running` + writer process dead → `interrupted` (reported as
///   interrupted, never as failed-by-policy)
public enum TrainingRunLiveness: Sendable, Equatable {
    case live(processIdentifier: Int32)
    case finished(TrainingRunLifecycleStatus)
    case paused(processAlive: Bool)
    case interrupted(lastHeartbeat: TrainingRunHeartbeat?)
}
