import Foundation

public struct PrivilegedDynamicsParameters: Sendable, Codable, Equatable {
    public let valuesByName: [String: Double]

    public init(valuesByName: [String: Double]) throws {
        for (name, value) in valuesByName {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PrivilegedDynamicsParametersError.emptyParameterName
            }
            guard value.isFinite else {
                throw PrivilegedDynamicsParametersError.nonFiniteValue(name: name)
            }
        }
        self.valuesByName = valuesByName
    }

    public func values(orderedBy names: [String]) throws -> [Double] {
        try names.map { name in
            guard let value = valuesByName[name] else {
                throw PrivilegedDynamicsParametersError.missingParameter(name: name)
            }
            return value
        }
    }
}

public enum PrivilegedDynamicsParametersError: Error, Sendable, Equatable {
    case emptyParameterName
    case missingParameter(name: String)
    case nonFiniteValue(name: String)
}
