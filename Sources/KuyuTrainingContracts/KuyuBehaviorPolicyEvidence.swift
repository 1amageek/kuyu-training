public struct KuyuBehaviorPolicyEvidence: Sendable, Codable, Equatable {
    public static let currentDistributionVersion = 2

    public enum DistributionKind: String, Sendable, Codable, Equatable {
        case affineTanhGaussian
        case affineSigmoidGaussian
        case identityGaussian
    }

    public let policyID: String
    public let checkpointDigest: String
    public let distributionKinds: [DistributionKind]
    public let distributionVersion: Int
    public let distributionContractDigest: String
    public let baseMean: [Double]
    public let transformedMean: [Double]
    public let baseLogStandardDeviation: [Double]
    public let preTransformSample: [Double]
    public let transformedAction: [Double]
    public let logProbability: Double
    public let rewardValue: Double?
    public let costValue: Double?
    public let inputRecurrentStateDigest: String?
    public let outputRecurrentStateDigest: String?

    public init(
        policyID: String,
        checkpointDigest: String,
        distributionKinds: [DistributionKind],
        distributionVersion: Int,
        distributionContractDigest: String,
        baseMean: [Double],
        transformedMean: [Double],
        baseLogStandardDeviation: [Double],
        preTransformSample: [Double],
        transformedAction: [Double],
        logProbability: Double,
        rewardValue: Double? = nil,
        costValue: Double? = nil,
        inputRecurrentStateDigest: String? = nil,
        outputRecurrentStateDigest: String? = nil
    ) {
        self.policyID = policyID
        self.checkpointDigest = checkpointDigest
        self.distributionKinds = distributionKinds
        self.distributionVersion = distributionVersion
        self.distributionContractDigest = distributionContractDigest
        self.baseMean = baseMean
        self.transformedMean = transformedMean
        self.baseLogStandardDeviation = baseLogStandardDeviation
        self.preTransformSample = preTransformSample
        self.transformedAction = transformedAction
        self.logProbability = logProbability
        self.rewardValue = rewardValue
        self.costValue = costValue
        self.inputRecurrentStateDigest = inputRecurrentStateDigest
        self.outputRecurrentStateDigest = outputRecurrentStateDigest
    }
}
