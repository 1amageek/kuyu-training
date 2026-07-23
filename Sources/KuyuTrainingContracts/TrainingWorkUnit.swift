import Foundation

public struct TrainingWorkUnit: Codable, Sendable, Hashable {
    public let kind: TrainingWorkUnitKind
    public let identifier: String
    public let suiteIndex: Int?
    public let scenarioID: String?
    public let scenarioSeed: UInt64?

    private enum CodingKeys: String, CodingKey {
        case kind
        case identifier
        case suiteIndex
        case scenarioID
        case scenarioSeed
    }

    public init(
        kind: TrainingWorkUnitKind,
        identifier: String,
        suiteIndex: Int? = nil,
        scenarioID: String? = nil,
        scenarioSeed: UInt64? = nil
    ) throws {
        guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TrainingWorkContractError.emptyIdentifier("workUnit.identifier")
        }
        if let suiteIndex, suiteIndex < 0 {
            throw TrainingWorkContractError.negativeIndex("suiteIndex", suiteIndex)
        }
        if let scenarioID,
           scenarioID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TrainingWorkContractError.emptyIdentifier("scenarioID")
        }
        self.kind = kind
        self.identifier = identifier
        self.suiteIndex = suiteIndex
        self.scenarioID = scenarioID
        self.scenarioSeed = scenarioSeed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: container.decode(TrainingWorkUnitKind.self, forKey: .kind),
            identifier: container.decode(String.self, forKey: .identifier),
            suiteIndex: container.decodeIfPresent(Int.self, forKey: .suiteIndex),
            scenarioID: container.decodeIfPresent(String.self, forKey: .scenarioID),
            scenarioSeed: container.decodeIfPresent(UInt64.self, forKey: .scenarioSeed)
        )
    }
}
