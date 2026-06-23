public struct TrainingTensorShape: Sendable, Codable, Equatable {
    public let dimensions: [Int]

    public init(_ dimensions: [Int]) throws {
        guard !dimensions.isEmpty else {
            throw TrainingTensorShapeError.emptyDimensions
        }
        for dimension in dimensions where dimension <= 0 {
            throw TrainingTensorShapeError.nonPositiveDimension(dimension)
        }
        self.dimensions = dimensions
    }

    public var elementCount: Int {
        dimensions.reduce(1, *)
    }
}

public enum TrainingTensorShapeError: Error, Sendable, Equatable {
    case emptyDimensions
    case nonPositiveDimension(Int)
    case elementCountMismatch(expected: Int, actual: Int)
}
