import Foundation

/// Behavior-policy statistics captured at the time a rollout action was
/// generated. PPO must use these values instead of reconstructing them from a
/// later model snapshot.
public struct RolloutBehaviorStatistics: Sendable, Codable, Equatable {
    public enum DistributionKind: String, Sendable, Codable, Equatable {
        case affineTanhGaussian
        case affineSigmoidGaussian
        case identityGaussian
    }

    public enum ValidationError: Error, Sendable, Equatable {
        case emptyMean
        case nonFiniteMean(index: Int)
        case nonFiniteLogProbability
        case incompleteExactEvidence
        case exactEvidenceDimensionMismatch
        case nonFiniteExactEvidence(field: String, index: Int)
        case invalidDistributionVersion(Int)
        case emptyDistributionContractDigest
        case unsupportedExactDistribution(index: Int)
    }

    public let mean: [Double]
    public let logProbability: Double
    public let distributionKinds: [DistributionKind]?
    public let distributionVersion: Int?
    public let distributionContractDigest: String?
    public let baseMean: [Double]?
    public let transformedMean: [Double]?
    public let baseLogStandardDeviation: [Double]?
    public let preTransformSample: [Double]?
    public let transformedAction: [Double]?

    public init(
        mean: [Double],
        logProbability: Double,
        distributionKinds: [DistributionKind]? = nil,
        distributionVersion: Int? = nil,
        distributionContractDigest: String? = nil,
        baseMean: [Double]? = nil,
        transformedMean: [Double]? = nil,
        baseLogStandardDeviation: [Double]? = nil,
        preTransformSample: [Double]? = nil,
        transformedAction: [Double]? = nil
    ) throws {
        guard !mean.isEmpty else {
            throw ValidationError.emptyMean
        }
        for (index, value) in mean.enumerated() where !value.isFinite {
            throw ValidationError.nonFiniteMean(index: index)
        }
        guard logProbability.isFinite else {
            throw ValidationError.nonFiniteLogProbability
        }
        let exactFields = [
            distributionKinds != nil,
            distributionVersion != nil,
            distributionContractDigest != nil,
            baseMean != nil,
            transformedMean != nil,
            baseLogStandardDeviation != nil,
            preTransformSample != nil,
            transformedAction != nil,
        ]
        guard exactFields.allSatisfy({ $0 }) || exactFields.allSatisfy({ !$0 }) else {
            throw ValidationError.incompleteExactEvidence
        }
        if let distributionKinds,
           let distributionVersion,
           let distributionContractDigest,
           let baseMean,
           let transformedMean,
           let baseLogStandardDeviation,
           let preTransformSample,
           let transformedAction {
            guard distributionKinds.count == mean.count,
                  baseMean.count == mean.count,
                  transformedMean.count == mean.count,
                  baseLogStandardDeviation.count == mean.count,
                  preTransformSample.count == mean.count,
                  transformedAction.count == mean.count else {
                throw ValidationError.exactEvidenceDimensionMismatch
            }
            guard distributionVersion > 0 else {
                throw ValidationError.invalidDistributionVersion(distributionVersion)
            }
            guard !distributionContractDigest.isEmpty else {
                throw ValidationError.emptyDistributionContractDigest
            }
            for values in [baseMean, transformedMean, baseLogStandardDeviation, preTransformSample, transformedAction] {
                for (index, value) in values.enumerated() where !value.isFinite {
                    throw ValidationError.nonFiniteExactEvidence(field: "distribution", index: index)
                }
            }
        }
        self.mean = mean
        self.logProbability = logProbability
        self.distributionKinds = distributionKinds
        self.distributionVersion = distributionVersion
        self.distributionContractDigest = distributionContractDigest
        self.baseMean = baseMean
        self.transformedMean = transformedMean
        self.baseLogStandardDeviation = baseLogStandardDeviation
        self.preTransformSample = preTransformSample
        self.transformedAction = transformedAction
    }
}
