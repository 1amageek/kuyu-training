public struct LearningUpdateMetrics: Sendable, Codable, Equatable {
  public let updateCount: UInt64
  public let policyLoss: Float
  public let rewardValueLoss: Float
  public let costValueLoss: Float
  public let entropy: Float
  public let approximateKL: Float
  public let clipFraction: Float
  public let rewardAdvantageMean: Float
  public let costAdvantageMean: Float
  public let gradientNorm: Float
  public let lagrangeMultiplier: Float

  public init(
    updateCount: UInt64,
    policyLoss: Float,
    rewardValueLoss: Float,
    costValueLoss: Float,
    entropy: Float,
    approximateKL: Float,
    clipFraction: Float,
    rewardAdvantageMean: Float,
    costAdvantageMean: Float,
    gradientNorm: Float,
    lagrangeMultiplier: Float
  ) {
    self.updateCount = updateCount
    self.policyLoss = policyLoss
    self.rewardValueLoss = rewardValueLoss
    self.costValueLoss = costValueLoss
    self.entropy = entropy
    self.approximateKL = approximateKL
    self.clipFraction = clipFraction
    self.rewardAdvantageMean = rewardAdvantageMean
    self.costAdvantageMean = costAdvantageMean
    self.gradientNorm = gradientNorm
    self.lagrangeMultiplier = lagrangeMultiplier
  }
}
