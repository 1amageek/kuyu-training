public enum KuyuTrajectoryBoundary: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable, Equatable {
        case continues
        case terminal
        case truncated
        case segmentEnd
    }

    public enum TerminalOutcome: String, Sendable, Codable, Equatable {
        case success
        case failure
    }

    public struct Terminal: Sendable, Codable, Equatable {
        public let outcome: TerminalOutcome
        public let reason: String

        public init(outcome: TerminalOutcome, reason: String) {
            self.outcome = outcome
            self.reason = reason
        }
    }

    public struct Truncation: Sendable, Codable, Equatable {
        public let reason: String
        public let bootstrapAllowed: Bool

        public init(reason: String, bootstrapAllowed: Bool) {
            self.reason = reason
            self.bootstrapAllowed = bootstrapAllowed
        }
    }

    public struct SegmentEnd: Sendable, Codable, Equatable {
        public let bootstrapAllowed: Bool
        public let continuationToken: String?

        public init(bootstrapAllowed: Bool, continuationToken: String? = nil) {
            self.bootstrapAllowed = bootstrapAllowed
            self.continuationToken = continuationToken
        }
    }

    case continues
    case terminal(Terminal)
    case truncated(Truncation)
    case segmentEnd(SegmentEnd)

    public var kind: Kind {
        switch self {
        case .continues: .continues
        case .terminal: .terminal
        case .truncated: .truncated
        case .segmentEnd: .segmentEnd
        }
    }

    public var bootstrapAllowed: Bool {
        switch self {
        case .continues:
            true
        case .terminal:
            false
        case .truncated(let value):
            value.bootstrapAllowed
        case .segmentEnd(let value):
            value.bootstrapAllowed
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case terminal
        case truncation
        case segmentEnd
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .continues:
            self = .continues
        case .terminal:
            self = .terminal(try container.decode(Terminal.self, forKey: .terminal))
        case .truncated:
            self = .truncated(try container.decode(Truncation.self, forKey: .truncation))
        case .segmentEnd:
            self = .segmentEnd(try container.decode(SegmentEnd.self, forKey: .segmentEnd))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .continues:
            break
        case .terminal(let value):
            try container.encode(value, forKey: .terminal)
        case .truncated(let value):
            try container.encode(value, forKey: .truncation)
        case .segmentEnd(let value):
            try container.encode(value, forKey: .segmentEnd)
        }
    }
}
