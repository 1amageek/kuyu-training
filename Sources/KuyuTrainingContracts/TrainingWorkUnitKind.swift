public enum TrainingWorkUnitKind: String, Codable, Sendable, Hashable {
    case scenario
    case controlStep
    case epoch
    case batch
    case candidate
}
