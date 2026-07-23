import Foundation
import KuyuTrainingContracts

extension TrainingRunWorkerLaunchArtifactV4.PolicyContract {
  init(_ contract: LearningProjectPolicyContract) {
    self.init(
      architecture: contract.architecture.rawValue,
      actionEncoding: contract.actionEncoding.rawValue,
      actionDistribution: .init(contract.actionDistribution),
      actionDimension: contract.actionDimension,
      temporalWindow: .init(contract.temporalWindow),
      privilegedCritic: .init(contract.privilegedCritic),
      behaviorCloning: .init(contract.behaviorCloning),
      ppo: .init(contract.ppo),
      domainRandomization: .init(contract.domainRandomization),
      actionSafety: .init(contract.actionSafety)
    )
  }

  func domainContract() throws -> LearningProjectPolicyContract {
    guard actionDimension > 0 else {
      throw invalid("policyContract.actionDimension", "must be greater than zero")
    }
    return LearningProjectPolicyContract(
      architecture: try rawValue(architecture, field: "policyContract.architecture"),
      actionEncoding: try rawValue(actionEncoding, field: "policyContract.actionEncoding"),
      actionDistribution: try actionDistribution.domainContract(),
      actionDimension: actionDimension,
      temporalWindow: try temporalWindow.domainContract(),
      privilegedCritic: try privilegedCritic.domainContract(),
      behaviorCloning: try behaviorCloning.domainContract(),
      ppo: try ppo.domainContract(),
      domainRandomization: try domainRandomization.domainContract(),
      actionSafety: try actionSafety.domainContract()
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.ActionDistribution {
  init(_ contract: LearningProjectPolicyActionDistributionContract) {
    self.init(
      kind: contract.kind.rawValue,
      densityContractID: contract.densityContractID,
      baseLogStandardDeviations: contract.baseLogStandardDeviations
    )
  }

  func domainContract() throws -> LearningProjectPolicyActionDistributionContract {
    LearningProjectPolicyActionDistributionContract(
      kind: try rawValue(kind, field: "policyContract.actionDistribution.kind"),
      densityContractID: densityContractID,
      baseLogStandardDeviations: try baseLogStandardDeviations.enumerated().map { index, value in
        try finite(
          value,
          field: "policyContract.actionDistribution.baseLogStandardDeviations[\(index)]"
        )
      }
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.TemporalWindow {
  init(_ contract: LearningProjectTemporalWindowContract) {
    self.init(
      historyLength: contract.historyLength,
      observationDimension: contract.observationDimension,
      previousActionDimension: contract.previousActionDimension,
      targetTrajectoryPointCount: contract.targetTrajectoryPointCount,
      executionMode: contract.execution.mode.rawValue,
      paddingRule: contract.execution.paddingRule.rawValue,
      previousActionRule: contract.execution.previousActionRule.rawValue
    )
  }

  func domainContract() throws -> LearningProjectTemporalWindowContract {
    guard historyLength > 0 else {
      throw invalid("policyContract.temporalWindow.historyLength", "must be greater than zero")
    }
    guard observationDimension > 0 else {
      throw invalid(
        "policyContract.temporalWindow.observationDimension",
        "must be greater than zero"
      )
    }
    guard previousActionDimension >= 0, targetTrajectoryPointCount >= 0 else {
      throw invalid("policyContract.temporalWindow", "dimensions must not be negative")
    }
    return LearningProjectTemporalWindowContract(
      historyLength: historyLength,
      observationDimension: observationDimension,
      previousActionDimension: previousActionDimension,
      targetTrajectoryPointCount: targetTrajectoryPointCount,
      execution: LearningProjectTemporalExecutionContract(
        mode: try rawValue(
          executionMode,
          field: "policyContract.temporalWindow.executionMode"
        ),
        paddingRule: try rawValue(
          paddingRule,
          field: "policyContract.temporalWindow.paddingRule"
        ),
        previousActionRule: try rawValue(
          previousActionRule,
          field: "policyContract.temporalWindow.previousActionRule"
        )
      )
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.PrivilegedCritic {
  init(_ contract: LearningProjectPrivilegedCriticContract) {
    self.init(
      isEnabled: contract.isEnabled,
      privilegedDimension: contract.privilegedDimension,
      parameterNames: contract.parameterNames
    )
  }

  func domainContract() throws -> LearningProjectPrivilegedCriticContract {
    guard privilegedDimension >= 0 else {
      throw invalid("policyContract.privilegedCritic.privilegedDimension", "must not be negative")
    }
    return LearningProjectPrivilegedCriticContract(
      isEnabled: isEnabled,
      privilegedDimension: privilegedDimension,
      parameterNames: parameterNames
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.BehaviorCloning {
  init(_ contract: LearningProjectBehaviorCloningContract) {
    self.init(
      isEnabled: contract.isEnabled,
      loss: contract.loss,
      initialCoefficient: contract.initialCoefficient,
      finalCoefficient: contract.finalCoefficient
    )
  }

  func domainContract() throws -> LearningProjectBehaviorCloningContract {
    LearningProjectBehaviorCloningContract(
      isEnabled: isEnabled,
      loss: loss,
      initialCoefficient: try finite(
        initialCoefficient,
        field: "policyContract.behaviorCloning.initialCoefficient"
      ),
      finalCoefficient: try finite(
        finalCoefficient,
        field: "policyContract.behaviorCloning.finalCoefficient"
      )
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.PPO {
  init(_ contract: LearningProjectPPOContract) {
    self.init(
      isEnabled: contract.isEnabled,
      clipEpsilon: contract.clipEpsilon,
      discount: contract.discount,
      gaeLambda: contract.gaeLambda,
      valueLossCoefficient: contract.valueLossCoefficient,
      actionSmoothnessCoefficient: contract.actionSmoothnessCoefficient,
      entropyRegularization: contract.entropyRegularization.rawValue,
      epochCount: contract.epochCount,
      minibatchSize: contract.minibatchSize
    )
  }

  func domainContract() throws -> LearningProjectPPOContract {
    guard epochCount > 0, minibatchSize > 0 else {
      throw invalid("policyContract.ppo", "epochCount and minibatchSize must be positive")
    }
    return LearningProjectPPOContract(
      isEnabled: isEnabled,
      clipEpsilon: try finite(clipEpsilon, field: "policyContract.ppo.clipEpsilon"),
      discount: try finite(discount, field: "policyContract.ppo.discount"),
      gaeLambda: try finite(gaeLambda, field: "policyContract.ppo.gaeLambda"),
      valueLossCoefficient: try finite(
        valueLossCoefficient,
        field: "policyContract.ppo.valueLossCoefficient"
      ),
      actionSmoothnessCoefficient: try finite(
        actionSmoothnessCoefficient,
        field: "policyContract.ppo.actionSmoothnessCoefficient"
      ),
      entropyRegularization: try rawValue(
        entropyRegularization,
        field: "policyContract.ppo.entropyRegularization"
      ),
      epochCount: epochCount,
      minibatchSize: minibatchSize
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.DomainRandomization {
  init(_ contract: LearningProjectDomainRandomizationContract) {
    self.init(
      isEnabled: contract.isEnabled,
      parameters: contract.parameters.map(TrainingRunWorkerLaunchArtifactV4.DomainRandomizationParameter.init),
      maximumActionLatencySteps: contract.maximumActionLatencySteps,
      maximumWindMetersPerSecond: contract.maximumWindMetersPerSecond
    )
  }

  func domainContract() throws -> LearningProjectDomainRandomizationContract {
    guard maximumActionLatencySteps >= 0 else {
      throw invalid(
        "policyContract.domainRandomization.maximumActionLatencySteps",
        "must not be negative"
      )
    }
    return LearningProjectDomainRandomizationContract(
      isEnabled: isEnabled,
      parameters: try parameters.map { try $0.domainParameter() },
      maximumActionLatencySteps: maximumActionLatencySteps,
      maximumWindMetersPerSecond: try finite(
        maximumWindMetersPerSecond,
        field: "policyContract.domainRandomization.maximumWindMetersPerSecond"
      )
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.DomainRandomizationParameter {
  init(_ parameter: LearningProjectDomainRandomizationParameter) {
    self.init(
      name: parameter.name,
      lowerMultiplier: parameter.lowerMultiplier,
      upperMultiplier: parameter.upperMultiplier
    )
  }

  func domainParameter() throws -> LearningProjectDomainRandomizationParameter {
    LearningProjectDomainRandomizationParameter(
      name: name,
      lowerMultiplier: try finite(
        lowerMultiplier,
        field: "policyContract.domainRandomization.parameters.lowerMultiplier"
      ),
      upperMultiplier: try finite(
        upperMultiplier,
        field: "policyContract.domainRandomization.parameters.upperMultiplier"
      )
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.ActionSafety {
  init(_ contract: LearningProjectActionSafetyContract) {
    self.init(
      isEnabled: contract.isEnabled,
      lowerBounds: contract.lowerBounds,
      upperBounds: contract.upperBounds,
      smoothingAlpha: contract.smoothingAlpha
    )
  }

  func domainContract() throws -> LearningProjectActionSafetyContract {
    try lowerBounds.enumerated().forEach { index, value in
      _ = try finite(value, field: "policyContract.actionSafety.lowerBounds[\(index)]")
    }
    try upperBounds.enumerated().forEach { index, value in
      _ = try finite(value, field: "policyContract.actionSafety.upperBounds[\(index)]")
    }
    return LearningProjectActionSafetyContract(
      isEnabled: isEnabled,
      lowerBounds: lowerBounds,
      upperBounds: upperBounds,
      smoothingAlpha: try finite(
        smoothingAlpha,
        field: "policyContract.actionSafety.smoothingAlpha"
      )
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.ActionContract {
  init(_ contract: LearningProjectActionContract) {
    self.init(
      schemaID: contract.schemaID,
      kind: contract.kind.rawValue,
      driveCount: contract.driveCount,
      actuatorCount: contract.actuatorCount,
      isBounded: contract.isBounded,
      channels: contract.channels.map(TrainingRunWorkerLaunchArtifactV4.ActionChannel.init),
      groups: contract.groups.map(TrainingRunWorkerLaunchArtifactV4.ActionGroup.init),
      couplingRules: contract.couplingRules.map(
        TrainingRunWorkerLaunchArtifactV4.ActionCouplingRule.init
      )
    )
  }

  func domainContract() throws -> LearningProjectActionContract {
    LearningProjectActionContract(
      schemaID: schemaID,
      kind: try rawValue(kind, field: "actionContract.kind"),
      driveCount: driveCount,
      actuatorCount: actuatorCount,
      isBounded: isBounded,
      channels: try channels.map { try $0.domainChannel() },
      groups: try groups.map { try $0.domainGroup() },
      couplingRules: try couplingRules.map { try $0.domainRule() }
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.ActionChannel {
  init(_ channel: LearningProjectActionChannel) {
    self.init(
      index: channel.index,
      name: channel.name,
      unit: channel.unit,
      normalizedLowerBound: channel.normalizedLowerBound,
      normalizedUpperBound: channel.normalizedUpperBound,
      outputTransform: channel.outputTransform.rawValue
    )
  }

  func domainChannel() throws -> LearningProjectActionChannel {
    LearningProjectActionChannel(
      index: index,
      name: name,
      unit: unit,
      normalizedLowerBound: try finite(
        normalizedLowerBound,
        field: "actionContract.channels.normalizedLowerBound"
      ),
      normalizedUpperBound: try finite(
        normalizedUpperBound,
        field: "actionContract.channels.normalizedUpperBound"
      ),
      outputTransform: try rawValue(
        outputTransform,
        field: "actionContract.channels.outputTransform"
      )
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.ActionGroup {
  init(_ group: LearningProjectActionGroup) {
    self.init(
      groupID: group.groupID,
      displayName: group.displayName,
      channelIndices: group.channelIndices,
      parentGroupID: group.parentGroupID,
      role: group.role.rawValue
    )
  }

  func domainGroup() throws -> LearningProjectActionGroup {
    LearningProjectActionGroup(
      groupID: groupID,
      displayName: displayName,
      channelIndices: channelIndices,
      parentGroupID: parentGroupID,
      role: try rawValue(role, field: "actionContract.groups.role")
    )
  }
}

extension TrainingRunWorkerLaunchArtifactV4.ActionCouplingRule {
  init(_ rule: LearningProjectActionCouplingRule) {
    self.init(
      ruleID: rule.ruleID,
      kind: rule.kind.rawValue,
      sourceGroupID: rule.sourceGroupID,
      targetGroupID: rule.targetGroupID,
      channelIndices: rule.channelIndices,
      coefficient: rule.coefficient
    )
  }

  func domainRule() throws -> LearningProjectActionCouplingRule {
    LearningProjectActionCouplingRule(
      ruleID: ruleID,
      kind: try rawValue(kind, field: "actionContract.couplingRules.kind"),
      sourceGroupID: sourceGroupID,
      targetGroupID: targetGroupID,
      channelIndices: channelIndices,
      coefficient: try coefficient.map {
        try finite($0, field: "actionContract.couplingRules.coefficient")
      }
    )
  }
}
