import Foundation

public struct PopulationSeedRequest: Sendable, Equatable {
    public let runID: String
    public let populationSize: Int
    public let seed: UInt64
    public let artifactRoot: URL
    public let preservesIncumbent: Bool

    public init(
        runID: String,
        populationSize: Int,
        seed: UInt64,
        artifactRoot: URL,
        preservesIncumbent: Bool = true
    ) {
        self.runID = runID
        self.populationSize = max(1, populationSize)
        self.seed = seed
        self.artifactRoot = artifactRoot
        self.preservesIncumbent = preservesIncumbent
    }
}
