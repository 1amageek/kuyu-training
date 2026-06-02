import Foundation

public enum LearningProjectActionSpaceKind: String, Codable, Sendable, Equatable, CaseIterable {
    case continuous
    case discrete
    case hybrid
}

public enum LearningProjectActionOutputTransform: String, Codable, Sendable, Equatable, CaseIterable {
    case sigmoid
    case tanh
    case clampedLinear
    case identity
}

public enum LearningProjectActionGroupRole: String, Codable, Sendable, Equatable, CaseIterable {
    case actuator
    case primitive
    case bodyPart
    case synergy
    case stabilizer
}

public struct LearningProjectActionGroup: Codable, Sendable, Equatable {
    public let groupID: String
    public let displayName: String?
    public let channelIndices: [Int]
    public let parentGroupID: String?
    public let role: LearningProjectActionGroupRole

    public init(
        groupID: String,
        displayName: String? = nil,
        channelIndices: [Int],
        parentGroupID: String? = nil,
        role: LearningProjectActionGroupRole
    ) {
        self.groupID = groupID
        self.displayName = displayName
        self.channelIndices = channelIndices
        self.parentGroupID = parentGroupID
        self.role = role
    }
}

public enum LearningProjectActionCouplingKind: String, Codable, Sendable, Equatable, CaseIterable {
    case symmetric
    case antiSymmetric
    case synchronized
    case exclusive
    case custom
}

public struct LearningProjectActionCouplingRule: Codable, Sendable, Equatable {
    public let ruleID: String
    public let kind: LearningProjectActionCouplingKind
    public let sourceGroupID: String?
    public let targetGroupID: String?
    public let channelIndices: [Int]
    public let coefficient: Double?

    public init(
        ruleID: String,
        kind: LearningProjectActionCouplingKind,
        sourceGroupID: String? = nil,
        targetGroupID: String? = nil,
        channelIndices: [Int] = [],
        coefficient: Double? = nil
    ) {
        self.ruleID = ruleID
        self.kind = kind
        self.sourceGroupID = sourceGroupID
        self.targetGroupID = targetGroupID
        self.channelIndices = channelIndices
        self.coefficient = coefficient
    }
}

public struct LearningProjectActionChannel: Codable, Sendable, Equatable {
    public let index: Int
    public let name: String
    public let unit: String?
    public let normalizedLowerBound: Double
    public let normalizedUpperBound: Double
    public let outputTransform: LearningProjectActionOutputTransform

    public init(
        index: Int,
        name: String,
        unit: String?,
        normalizedLowerBound: Double,
        normalizedUpperBound: Double,
        outputTransform: LearningProjectActionOutputTransform
    ) {
        self.index = index
        self.name = name
        self.unit = unit
        self.normalizedLowerBound = normalizedLowerBound
        self.normalizedUpperBound = normalizedUpperBound
        self.outputTransform = outputTransform
    }
}

public struct LearningProjectActionContract: Codable, Sendable, Equatable {
    public let schemaID: String
    public let kind: LearningProjectActionSpaceKind
    public let driveCount: Int?
    public let actuatorCount: Int?
    public let isBounded: Bool
    public let channels: [LearningProjectActionChannel]
    public let groups: [LearningProjectActionGroup]
    public let couplingRules: [LearningProjectActionCouplingRule]

    public init(
        schemaID: String,
        kind: LearningProjectActionSpaceKind,
        driveCount: Int?,
        actuatorCount: Int?,
        isBounded: Bool,
        channels: [LearningProjectActionChannel],
        groups: [LearningProjectActionGroup] = [],
        couplingRules: [LearningProjectActionCouplingRule] = []
    ) {
        self.schemaID = schemaID
        self.kind = kind
        self.driveCount = driveCount
        self.actuatorCount = actuatorCount
        self.isBounded = isBounded
        self.channels = channels
        self.groups = groups
        self.couplingRules = couplingRules
    }

    private enum CodingKeys: String, CodingKey {
        case schemaID
        case kind
        case driveCount
        case actuatorCount
        case isBounded
        case channels
        case groups
        case couplingRules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaID = try container.decode(String.self, forKey: .schemaID)
        self.kind = try container.decode(LearningProjectActionSpaceKind.self, forKey: .kind)
        self.driveCount = try container.decodeIfPresent(Int.self, forKey: .driveCount)
        self.actuatorCount = try container.decodeIfPresent(Int.self, forKey: .actuatorCount)
        self.isBounded = try container.decode(Bool.self, forKey: .isBounded)
        self.channels = try container.decode([LearningProjectActionChannel].self, forKey: .channels)
        self.groups = try container.decodeIfPresent([LearningProjectActionGroup].self, forKey: .groups) ?? []
        self.couplingRules = try container.decodeIfPresent(
            [LearningProjectActionCouplingRule].self,
            forKey: .couplingRules
        ) ?? []
    }

    public static func boundedChannels(
        names: [String],
        unit: String?,
        lowerBound: Double,
        upperBound: Double,
        transform: LearningProjectActionOutputTransform
    ) -> [LearningProjectActionChannel] {
        names.enumerated().map { index, name in
            LearningProjectActionChannel(
                index: index,
                name: name,
                unit: unit,
                normalizedLowerBound: lowerBound,
                normalizedUpperBound: upperBound,
                outputTransform: transform
            )
        }
    }

    public static func indexedBoundedChannels(
        prefix: String,
        count: Int,
        unit: String?,
        lowerBound: Double,
        upperBound: Double,
        transform: LearningProjectActionOutputTransform
    ) -> [LearningProjectActionChannel] {
        boundedChannels(
            names: (0..<count).map { "\(prefix)\($0)" },
            unit: unit,
            lowerBound: lowerBound,
            upperBound: upperBound,
            transform: transform
        )
    }
}
