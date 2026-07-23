import Foundation

public struct TrainingDatasetCurationPolicy: Sendable, Codable, Equatable {
    public let policyID: String
    public let minimumDatasetCount: Int
    public let minimumTotalRecordCount: Int
    public let minimumRecordCountPerDataset: Int
    public let requiredScenarioIDs: [String]
    public let allowedDeterminismTiers: [String]
    public let expectedChannelCount: Int?
    public let expectedDriveCount: Int?
    public let requiresRewardDescriptor: Bool
    public let requiresProvenance: Bool

    public init(
        policyID: String,
        minimumDatasetCount: Int = 1,
        minimumTotalRecordCount: Int = 1,
        minimumRecordCountPerDataset: Int = 1,
        requiredScenarioIDs: [String] = [],
        allowedDeterminismTiers: [String] = [],
        expectedChannelCount: Int? = nil,
        expectedDriveCount: Int? = nil,
        requiresRewardDescriptor: Bool = false,
        requiresProvenance: Bool = false
    ) {
        self.policyID = policyID
        self.minimumDatasetCount = minimumDatasetCount
        self.minimumTotalRecordCount = minimumTotalRecordCount
        self.minimumRecordCountPerDataset = minimumRecordCountPerDataset
        self.requiredScenarioIDs = requiredScenarioIDs
        self.allowedDeterminismTiers = allowedDeterminismTiers
        self.expectedChannelCount = expectedChannelCount
        self.expectedDriveCount = expectedDriveCount
        self.requiresRewardDescriptor = requiresRewardDescriptor
        self.requiresProvenance = requiresProvenance
    }
}
