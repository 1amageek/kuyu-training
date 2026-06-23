import Foundation
import KuyuTrainingContracts

public struct ReproductionRequest<Candidate: Sendable>: Sendable {
    public let runID: String
    public let generation: Int
    public let parents: [Candidate]
    public let targetPopulationSize: Int
    public let mutationRate: Double
    public let mutationNoiseScale: Double
    public let seed: UInt64
    public let artifactRoot: URL

    public init(
        runID: String,
        generation: Int,
        parents: [Candidate],
        targetPopulationSize: Int,
        mutationRate: Double,
        mutationNoiseScale: Double,
        seed: UInt64,
        artifactRoot: URL
    ) {
        self.runID = runID
        self.generation = max(0, generation)
        self.parents = parents
        self.targetPopulationSize = max(1, targetPopulationSize)
        self.mutationRate = max(0, mutationRate)
        self.mutationNoiseScale = max(0, mutationNoiseScale)
        self.seed = seed
        self.artifactRoot = artifactRoot
    }
}
