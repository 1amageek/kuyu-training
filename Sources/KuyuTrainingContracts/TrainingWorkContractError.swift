public enum TrainingWorkContractError: Error, Sendable, Equatable {
    case emptyIdentifier(String)
    case negativeIndex(String, Int)
    case invalidUnitCount(completed: Int, total: Int)
    case invalidPopulationSize(Int)
}
