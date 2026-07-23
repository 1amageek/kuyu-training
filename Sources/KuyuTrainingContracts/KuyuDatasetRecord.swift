public enum KuyuDatasetRecord: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable, Equatable {
        case demonstration
        case onPolicyTransition
        case offPolicyTransition
        case worldTransition
    }

    case demonstration(KuyuDemonstrationSample)
    case onPolicyTransition(KuyuOnPolicyTransition)
    case offPolicyTransition(KuyuOffPolicyTransition)
    case worldTransition(KuyuWorldTransition)

    public var kind: Kind {
        switch self {
        case .demonstration: .demonstration
        case .onPolicyTransition: .onPolicyTransition
        case .offPolicyTransition: .offPolicyTransition
        case .worldTransition: .worldTransition
        }
    }

    public var coordinate: KuyuTrajectoryCoordinate {
        switch self {
        case .demonstration(let value): value.coordinate
        case .onPolicyTransition(let value): value.transition.coordinate
        case .offPolicyTransition(let value): value.transition.coordinate
        case .worldTransition(let value): value.coordinate
        }
    }

    public var boundary: KuyuTrajectoryBoundary? {
        switch self {
        case .demonstration:
            nil
        case .onPolicyTransition(let value):
            value.transition.boundary
        case .offPolicyTransition(let value):
            value.transition.boundary
        case .worldTransition(let value):
            value.boundary
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case demonstration
        case onPolicyTransition
        case offPolicyTransition
        case worldTransition
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .demonstration:
            self = .demonstration(try container.decode(KuyuDemonstrationSample.self, forKey: .demonstration))
        case .onPolicyTransition:
            self = .onPolicyTransition(
                try container.decode(KuyuOnPolicyTransition.self, forKey: .onPolicyTransition)
            )
        case .offPolicyTransition:
            self = .offPolicyTransition(
                try container.decode(KuyuOffPolicyTransition.self, forKey: .offPolicyTransition)
            )
        case .worldTransition:
            self = .worldTransition(try container.decode(KuyuWorldTransition.self, forKey: .worldTransition))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .demonstration(let value):
            try container.encode(value, forKey: .demonstration)
        case .onPolicyTransition(let value):
            try container.encode(value, forKey: .onPolicyTransition)
        case .offPolicyTransition(let value):
            try container.encode(value, forKey: .offPolicyTransition)
        case .worldTransition(let value):
            try container.encode(value, forKey: .worldTransition)
        }
    }
}
