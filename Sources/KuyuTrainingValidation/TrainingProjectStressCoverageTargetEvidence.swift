import KuyuScenarios

public struct TrainingProjectStressCoverageTargetEvidence: Sendable, Codable, Equatable {
    public let dimension: StressSuiteManifest.StressDimension
    public let minimumCount: Int
    public let actualCount: Int

    public init(
        dimension: StressSuiteManifest.StressDimension,
        minimumCount: Int,
        actualCount: Int
    ) {
        self.dimension = dimension
        self.minimumCount = minimumCount
        self.actualCount = actualCount
    }

    public init(
        target: StressSuiteManifest.CoverageTarget,
        manifest: StressSuiteManifest
    ) {
        self.init(
            dimension: target.dimension,
            minimumCount: target.minimumCount,
            actualCount: manifest.coverageCounts[target.dimension, default: 0]
        )
    }
}
