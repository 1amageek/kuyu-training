import Foundation

public struct TrainingWorkScope: Codable, Sendable, Hashable {
    public let runID: String
    public let iterationIndex: Int?
    public let generationIndex: Int?
    public let candidateID: String?
    public let batchID: String?
    public let batchIndex: Int?
    public let batchCount: Int?

    private enum CodingKeys: String, CodingKey {
        case runID
        case iterationIndex
        case generationIndex
        case candidateID
        case batchID
        case batchIndex
        case batchCount
    }

    public init(
        runID: String,
        iterationIndex: Int? = nil,
        generationIndex: Int? = nil,
        candidateID: String? = nil,
        batchID: String? = nil,
        batchIndex: Int? = nil,
        batchCount: Int? = nil
    ) throws {
        guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TrainingWorkContractError.emptyIdentifier("runID")
        }
        if let iterationIndex, iterationIndex < 0 {
            throw TrainingWorkContractError.negativeIndex("iterationIndex", iterationIndex)
        }
        if let generationIndex, generationIndex < 0 {
            throw TrainingWorkContractError.negativeIndex("generationIndex", generationIndex)
        }
        if let candidateID,
           candidateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TrainingWorkContractError.emptyIdentifier("candidateID")
        }
        if let batchID,
           batchID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TrainingWorkContractError.emptyIdentifier("batchID")
        }
        if let batchIndex, batchIndex < 0 {
            throw TrainingWorkContractError.negativeIndex("batchIndex", batchIndex)
        }
        if let batchCount, batchCount <= 0 {
            throw TrainingWorkContractError.invalidUnitCount(
                completed: batchIndex ?? 0,
                total: batchCount
            )
        }
        if let batchIndex, let batchCount, batchIndex >= batchCount {
            throw TrainingWorkContractError.invalidUnitCount(
                completed: batchIndex,
                total: batchCount
            )
        }
        self.runID = runID
        self.iterationIndex = iterationIndex
        self.generationIndex = generationIndex
        self.candidateID = candidateID
        self.batchID = batchID
        self.batchIndex = batchIndex
        self.batchCount = batchCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            runID: container.decode(String.self, forKey: .runID),
            iterationIndex: container.decodeIfPresent(Int.self, forKey: .iterationIndex),
            generationIndex: container.decodeIfPresent(Int.self, forKey: .generationIndex),
            candidateID: container.decodeIfPresent(String.self, forKey: .candidateID),
            batchID: container.decodeIfPresent(String.self, forKey: .batchID),
            batchIndex: container.decodeIfPresent(Int.self, forKey: .batchIndex),
            batchCount: container.decodeIfPresent(Int.self, forKey: .batchCount)
        )
    }
}
