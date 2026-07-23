import Foundation

/// The action emitted by a policy before the environment realizes it through
/// a control law or morphology-dependent actuator mapping.
public struct RolloutPolicyAction: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Sendable, Equatable {
        case emptyEncoding
        case emptyValues
        case nonFiniteValue(index: Int)
    }

    public let encoding: String
    public let values: [Double]

    public init(encoding: String, values: [Double]) throws {
        guard !encoding.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyEncoding
        }
        guard !values.isEmpty else {
            throw ValidationError.emptyValues
        }
        for (index, value) in values.enumerated() where !value.isFinite {
            throw ValidationError.nonFiniteValue(index: index)
        }
        self.encoding = encoding
        self.values = values
    }
}
