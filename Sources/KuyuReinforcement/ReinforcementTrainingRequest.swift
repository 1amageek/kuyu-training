import Foundation
import KuyuTrainingContracts

public struct ReinforcementTrainingRequest: Sendable, Equatable {
    public let runID: String
    public let stageID: String
    public let artifactRoot: URL
    public let seed: UInt64
    public let epochLimit: Int?

    public init(
        runID: String,
        stageID: String,
        artifactRoot: URL,
        seed: UInt64,
        epochLimit: Int? = nil
    ) {
        self.runID = runID
        self.stageID = stageID
        self.artifactRoot = artifactRoot
        self.seed = seed
        self.epochLimit = epochLimit.map { max(1, $0) }
    }
}
