public enum SelectionPressure: String, Sendable, Codable, Equatable, CaseIterable {
    case conservative
    case balanced
    case exploratory
}

public struct SelectionPolicy: Sendable, Codable, Equatable {
    public let eliteCount: Int
    public let parentCount: Int
    public let pressure: SelectionPressure
    public let preservesIncumbent: Bool

    public init(
        eliteCount: Int,
        parentCount: Int,
        pressure: SelectionPressure = .balanced,
        preservesIncumbent: Bool = true
    ) {
        self.eliteCount = max(1, eliteCount)
        self.parentCount = max(1, parentCount)
        self.pressure = pressure
        self.preservesIncumbent = preservesIncumbent
    }
}
