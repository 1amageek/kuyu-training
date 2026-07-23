import Foundation

public struct TrainingDatasetCurationReport: Sendable, Codable, Equatable {
    public let policyID: String
    public let accepted: Bool
    public let datasetIDs: [String]
    public let scenarioIDs: [String]
    public let datasetCount: Int
    public let totalRecordCount: Int
    public let minimumDatasetCount: Int
    public let minimumTotalRecordCount: Int
    public let minimumRecordCountPerDataset: Int

    public init(
        policyID: String,
        accepted: Bool,
        datasetIDs: [String],
        scenarioIDs: [String],
        datasetCount: Int,
        totalRecordCount: Int,
        minimumDatasetCount: Int,
        minimumTotalRecordCount: Int,
        minimumRecordCountPerDataset: Int
    ) {
        self.policyID = policyID
        self.accepted = accepted
        self.datasetIDs = datasetIDs
        self.scenarioIDs = scenarioIDs
        self.datasetCount = datasetCount
        self.totalRecordCount = totalRecordCount
        self.minimumDatasetCount = minimumDatasetCount
        self.minimumTotalRecordCount = minimumTotalRecordCount
        self.minimumRecordCountPerDataset = minimumRecordCountPerDataset
    }
}
