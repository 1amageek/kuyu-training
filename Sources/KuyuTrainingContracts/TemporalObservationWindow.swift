public struct TemporalObservationWindow: Sendable, Codable, Equatable {
    public let historyLength: Int
    public let observationDimension: Int
    public let values: [Double]

    public init(
        historyLength: Int,
        observationDimension: Int,
        values: [Double]
    ) throws {
        guard historyLength > 0 else {
            throw TemporalObservationWindowError.nonPositiveHistoryLength
        }
        guard observationDimension > 0 else {
            throw TemporalObservationWindowError.nonPositiveObservationDimension
        }
        let expectedCount = historyLength * observationDimension
        guard values.count == expectedCount else {
            throw TemporalObservationWindowError.valueCountMismatch(
                expected: expectedCount,
                actual: values.count
            )
        }
        guard values.allSatisfy(\.isFinite) else {
            throw TemporalObservationWindowError.nonFiniteValue
        }
        self.historyLength = historyLength
        self.observationDimension = observationDimension
        self.values = values
    }

    public var shape: [Int] {
        [historyLength, observationDimension]
    }
}

public enum TemporalObservationWindowError: Error, Sendable, Equatable {
    case nonPositiveHistoryLength
    case nonPositiveObservationDimension
    case valueCountMismatch(expected: Int, actual: Int)
    case nonFiniteValue
}
