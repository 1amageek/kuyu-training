import Foundation

public struct LearningProjectCurriculum: Codable, Sendable, Equatable {
    public let suiteIDs: [Int]
    public let seedCount: Int
    public let episodesPerSuite: Int
    public let populationSize: Int
    public let generationLimit: Int
    public let eliteCount: Int
    public let maxStepCount: Int?

    public init(
        suiteIDs: [Int],
        seedCount: Int,
        episodesPerSuite: Int,
        populationSize: Int,
        generationLimit: Int,
        eliteCount: Int,
        maxStepCount: Int?
    ) {
        self.suiteIDs = suiteIDs
        self.seedCount = seedCount
        self.episodesPerSuite = episodesPerSuite
        self.populationSize = populationSize
        self.generationLimit = generationLimit
        self.eliteCount = eliteCount
        self.maxStepCount = maxStepCount
    }
}
