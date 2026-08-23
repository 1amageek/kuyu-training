public struct LearningUpdatePlan: Sendable, Codable, Equatable {
  public let criticHiddenSize: Int
  public let initialPolicyLogStandardDeviation: Float
  public let rewardDiscount: Float
  public let rewardGAELambda: Float
  public let costDiscount: Float
  public let costGAELambda: Float
  public let policyClip: Float
  public let valueClip: Float
  public let valueLossCoefficient: Float
  public let costValueLossCoefficient: Float
  public let entropyCoefficient: Float
  public let maximumGradientNorm: Float
  public let epochCount: Int
  public let minibatchSize: Int
  public let costLimit: Float
  public let initialLagrangeMultiplier: Float
  public let lagrangeLearningRate: Float
  public let optimizerLearningRate: Float
  public let optimizerBeta1: Float
  public let optimizerBeta2: Float
  public let optimizerEpsilon: Float
  public let maximumTransitions: UInt64
  public let maximumScalars: Int

  public init(
    criticHiddenSize: Int = 128,
    initialPolicyLogStandardDeviation: Float = -0.5,
    rewardDiscount: Float = 0.99,
    rewardGAELambda: Float = 0.95,
    costDiscount: Float = 0.99,
    costGAELambda: Float = 0.95,
    policyClip: Float = 0.2,
    valueClip: Float = 0.2,
    valueLossCoefficient: Float = 0.5,
    costValueLossCoefficient: Float = 0.5,
    entropyCoefficient: Float = 0,
    maximumGradientNorm: Float = 0.5,
    epochCount: Int = 4,
    minibatchSize: Int = 256,
    costLimit: Float = 0,
    initialLagrangeMultiplier: Float = 0,
    lagrangeLearningRate: Float = 0.01,
    optimizerLearningRate: Float = 3.0e-4,
    optimizerBeta1: Float = 0.9,
    optimizerBeta2: Float = 0.999,
    optimizerEpsilon: Float = 1.0e-8,
    maximumTransitions: UInt64 = 256,
    maximumScalars: Int = 8_000_000
  ) {
    self.criticHiddenSize = criticHiddenSize
    self.initialPolicyLogStandardDeviation =
      initialPolicyLogStandardDeviation
    self.rewardDiscount = rewardDiscount
    self.rewardGAELambda = rewardGAELambda
    self.costDiscount = costDiscount
    self.costGAELambda = costGAELambda
    self.policyClip = policyClip
    self.valueClip = valueClip
    self.valueLossCoefficient = valueLossCoefficient
    self.costValueLossCoefficient = costValueLossCoefficient
    self.entropyCoefficient = entropyCoefficient
    self.maximumGradientNorm = maximumGradientNorm
    self.epochCount = epochCount
    self.minibatchSize = minibatchSize
    self.costLimit = costLimit
    self.initialLagrangeMultiplier = initialLagrangeMultiplier
    self.lagrangeLearningRate = lagrangeLearningRate
    self.optimizerLearningRate = optimizerLearningRate
    self.optimizerBeta1 = optimizerBeta1
    self.optimizerBeta2 = optimizerBeta2
    self.optimizerEpsilon = optimizerEpsilon
    self.maximumTransitions = maximumTransitions
    self.maximumScalars = maximumScalars
  }
}
