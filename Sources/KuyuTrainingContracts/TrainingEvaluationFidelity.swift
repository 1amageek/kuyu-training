import Foundation

public enum TrainingEvaluationFidelity: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Sendable, Equatable {
        case invalidMaximumControlSteps(Int)
        case unexpectedMaximumControlSteps(Int)
    }

    case fullScenario
    case screening(maximumControlStepsPerEpisode: Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case maximumControlStepsPerEpisode
    }

    private enum Kind: String, Codable {
        case fullScenario
        case screening
    }

    public var maximumControlStepsPerEpisode: Int? {
        switch self {
        case .fullScenario:
            nil
        case .screening(let maximumControlStepsPerEpisode):
            maximumControlStepsPerEpisode
        }
    }

    public var isFullScenario: Bool {
        if case .fullScenario = self {
            return true
        }
        return false
    }

    public func validate() throws {
        if case .screening(let maximumControlStepsPerEpisode) = self,
           maximumControlStepsPerEpisode <= 0 {
            throw ValidationError.invalidMaximumControlSteps(maximumControlStepsPerEpisode)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let maximumControlSteps = try container.decodeIfPresent(
            Int.self,
            forKey: .maximumControlStepsPerEpisode
        )
        switch kind {
        case .fullScenario:
            if let maximumControlSteps {
                throw ValidationError.unexpectedMaximumControlSteps(maximumControlSteps)
            }
            self = .fullScenario
        case .screening:
            guard let maximumControlSteps, maximumControlSteps > 0 else {
                throw ValidationError.invalidMaximumControlSteps(maximumControlSteps ?? 0)
            }
            self = .screening(maximumControlStepsPerEpisode: maximumControlSteps)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fullScenario:
            try container.encode(Kind.fullScenario, forKey: .kind)
        case .screening(let maximumControlStepsPerEpisode):
            try container.encode(Kind.screening, forKey: .kind)
            try container.encode(
                maximumControlStepsPerEpisode,
                forKey: .maximumControlStepsPerEpisode
            )
        }
    }
}
