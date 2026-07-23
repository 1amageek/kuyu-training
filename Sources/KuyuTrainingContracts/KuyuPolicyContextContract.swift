public enum KuyuPolicyContextContract: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable, Equatable {
        case fixedHistory
        case recurrent
    }

    public struct FixedHistory: Sendable, Codable, Equatable {
        public let historyLength: Int
        public let featureOrderDigest: String
        public let paddingRule: LearningProjectTemporalExecutionContract.PaddingRule
        public let previousActionRule: LearningProjectTemporalExecutionContract.PreviousActionRule

        public init(
            historyLength: Int,
            featureOrderDigest: String,
            paddingRule: LearningProjectTemporalExecutionContract.PaddingRule,
            previousActionRule: LearningProjectTemporalExecutionContract.PreviousActionRule
        ) {
            self.historyLength = historyLength
            self.featureOrderDigest = featureOrderDigest
            self.paddingRule = paddingRule
            self.previousActionRule = previousActionRule
        }
    }

    public struct Recurrent: Sendable, Codable, Equatable {
        public let stateSpaceDigest: String
        public let resetRule: String
        public let initialState: [Double]
        public let initialStateDigest: String
        public let burnInCount: Int
        public let lossStartTransitionIndex: Int

        public init(
            stateSpaceDigest: String,
            resetRule: String,
            initialState: [Double],
            initialStateDigest: String,
            burnInCount: Int,
            lossStartTransitionIndex: Int
        ) {
            self.stateSpaceDigest = stateSpaceDigest
            self.resetRule = resetRule
            self.initialState = initialState
            self.initialStateDigest = initialStateDigest
            self.burnInCount = burnInCount
            self.lossStartTransitionIndex = lossStartTransitionIndex
        }
    }

    case fixedHistory(FixedHistory)
    case recurrent(Recurrent)

    public var kind: Kind {
        switch self {
        case .fixedHistory: .fixedHistory
        case .recurrent: .recurrent
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case fixedHistory
        case recurrent
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .fixedHistory:
            self = .fixedHistory(try container.decode(FixedHistory.self, forKey: .fixedHistory))
        case .recurrent:
            self = .recurrent(try container.decode(Recurrent.self, forKey: .recurrent))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .fixedHistory(let value):
            try container.encode(value, forKey: .fixedHistory)
        case .recurrent(let value):
            try container.encode(value, forKey: .recurrent)
        }
    }
}
