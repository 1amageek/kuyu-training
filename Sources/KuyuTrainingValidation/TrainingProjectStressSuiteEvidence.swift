import KuyuScenarios

public struct TrainingProjectStressSuiteEvidence: Sendable, Codable, Equatable {
    public let suiteID: String
    public let profile: StressSuiteManifest.Profile
    public let recordCount: Int
    public let coverageTargets: [TrainingProjectStressCoverageTargetEvidence]
    public let replayStatus: StressSuiteManifest.ReplayEvidence.Status
    public let replayCheckCount: Int
    public let referenceM2BenchmarkEvidence: StressSuiteManifest.ReferenceM2BenchmarkEvidence?
    public let path: String

    public init(
        suiteID: String,
        profile: StressSuiteManifest.Profile,
        recordCount: Int,
        coverageTargets: [TrainingProjectStressCoverageTargetEvidence],
        replayStatus: StressSuiteManifest.ReplayEvidence.Status,
        replayCheckCount: Int,
        referenceM2BenchmarkEvidence: StressSuiteManifest.ReferenceM2BenchmarkEvidence? = nil,
        path: String
    ) {
        self.suiteID = suiteID
        self.profile = profile
        self.recordCount = recordCount
        self.coverageTargets = coverageTargets
        self.replayStatus = replayStatus
        self.replayCheckCount = replayCheckCount
        self.referenceM2BenchmarkEvidence = referenceM2BenchmarkEvidence
        self.path = path
    }

    public init(manifest: StressSuiteManifest, path: String) {
        self.init(
            suiteID: manifest.suiteID,
            profile: manifest.profile,
            recordCount: manifest.records.count,
            coverageTargets: manifest.coverageTargets.map {
                TrainingProjectStressCoverageTargetEvidence(target: $0, manifest: manifest)
            },
            replayStatus: manifest.replayEvidence.status,
            replayCheckCount: manifest.replayEvidence.checkCount,
            referenceM2BenchmarkEvidence: manifest.referenceM2BenchmarkEvidence,
            path: path
        )
    }

    public var fulfilledCoverageDimensions: Set<StressSuiteManifest.StressDimension> {
        Set(coverageTargets.compactMap { target in
            target.actualCount >= target.minimumCount ? target.dimension : nil
        })
    }

    public var coversReferenceM2Benchmark: Bool {
        guard profile == .referenceQuadrotor else {
            return false
        }
        let dimensions = fulfilledCoverageDimensions
        return referenceM2BenchmarkEvidence?.isComplete == true
            && StressSuiteManifest.requiredReferenceQuadrotorM2Dimensions.allSatisfy {
            dimensions.contains($0)
        }
    }
}
