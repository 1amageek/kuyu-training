import Foundation

public enum LearningProjectPolicyActionDistribution: String, Codable, Sendable, Equatable, CaseIterable {
    case deterministic
    case gaussian
}

public struct LearningProjectPolicyActionDistributionContract: Codable, Sendable, Equatable {
    public static let deterministicDensityContractID = "deterministic-point-mass-v1"
    /// Diagonal Gaussian in pre-transform coordinates. Rollouts persist the
    /// sampled pre-transform value; PPO never reconstructs it with an inverse.
    public static let fixedGaussianDensityContractID = "pretransform-diagonal-fixed-gaussian-v2"

    public let kind: LearningProjectPolicyActionDistribution
    public let densityContractID: String
    public let baseLogStandardDeviations: [Double]

    public init(
        kind: LearningProjectPolicyActionDistribution,
        densityContractID: String,
        baseLogStandardDeviations: [Double]
    ) {
        self.kind = kind
        self.densityContractID = densityContractID
        self.baseLogStandardDeviations = baseLogStandardDeviations
    }

    public static let deterministic = LearningProjectPolicyActionDistributionContract(
        kind: .deterministic,
        densityContractID: deterministicDensityContractID,
        baseLogStandardDeviations: []
    )

    public static func fixedGaussian(
        actionDimension: Int,
        baseLogStandardDeviation: Double = -3.2
    ) -> LearningProjectPolicyActionDistributionContract {
        LearningProjectPolicyActionDistributionContract(
            kind: .gaussian,
            densityContractID: fixedGaussianDensityContractID,
            baseLogStandardDeviations: Array(
                repeating: baseLogStandardDeviation,
                count: max(0, actionDimension)
            )
        )
    }
}
