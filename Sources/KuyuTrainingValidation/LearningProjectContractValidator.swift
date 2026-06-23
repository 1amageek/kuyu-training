import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public enum LearningProjectContractValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidObservation(reason: String)
    case invalidAction(reason: String)
    case invalidPolicy(reason: String)

    public var description: String {
        switch self {
        case .invalidObservation(let reason):
            return "invalid-observation-contract reason=\(reason)"
        case .invalidAction(let reason):
            return "invalid-action-contract reason=\(reason)"
        case .invalidPolicy(let reason):
            return "invalid-policy-contract reason=\(reason)"
        }
    }
}

public struct LearningProjectContractValidator: Sendable {
    public init() {}

    public func validate(
        observation: LearningProjectObservationContract,
        action: LearningProjectActionContract,
        policy: LearningProjectPolicyContract
    ) throws {
        try validateObservation(observation)
        try validateAction(action)
        try validatePolicy(policy, observation: observation, action: action)
    }

    public func validateObservation(_ observation: LearningProjectObservationContract) throws {
        if observation.schemaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LearningProjectContractValidationError.invalidObservation(reason: "empty-schema-id")
        }
        if observation.channelCount <= 0 {
            throw LearningProjectContractValidationError.invalidObservation(reason: "non-positive-channel-count")
        }
        if observation.channels.count != observation.channelCount {
            throw LearningProjectContractValidationError.invalidObservation(reason: "channel-count-mismatch")
        }
        var seen: Set<Int> = []
        for channel in observation.channels {
            if channel.index < 0 || channel.index >= observation.channelCount {
                throw LearningProjectContractValidationError.invalidObservation(reason: "channel-index-out-of-range")
            }
            if seen.contains(channel.index) {
                throw LearningProjectContractValidationError.invalidObservation(reason: "duplicate-channel-index")
            }
            if channel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw LearningProjectContractValidationError.invalidObservation(reason: "empty-channel-name")
            }
            seen.insert(channel.index)
        }
    }

    public func validateAction(_ action: LearningProjectActionContract) throws {
        if action.schemaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LearningProjectContractValidationError.invalidAction(reason: "empty-schema-id")
        }
        if let driveCount = action.driveCount, driveCount <= 0 {
            throw LearningProjectContractValidationError.invalidAction(reason: "non-positive-drive-count")
        }
        if let actuatorCount = action.actuatorCount, actuatorCount <= 0 {
            throw LearningProjectContractValidationError.invalidAction(reason: "non-positive-actuator-count")
        }
        if action.driveCount == nil && action.actuatorCount == nil {
            throw LearningProjectContractValidationError.invalidAction(reason: "missing-drive-or-actuator-count")
        }
        let expectedChannelCount = action.driveCount ?? action.actuatorCount ?? 0
        if action.channels.count != expectedChannelCount {
            throw LearningProjectContractValidationError.invalidAction(reason: "action-channel-count-mismatch")
        }
        for (expectedIndex, channel) in action.channels.enumerated() {
            if channel.index != expectedIndex {
                throw LearningProjectContractValidationError.invalidAction(reason: "action-channel-index-mismatch")
            }
            if channel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw LearningProjectContractValidationError.invalidAction(reason: "empty-action-channel-name")
            }
            if !channel.normalizedLowerBound.isFinite || !channel.normalizedUpperBound.isFinite ||
                channel.normalizedUpperBound < channel.normalizedLowerBound {
                throw LearningProjectContractValidationError.invalidAction(reason: "invalid-action-channel-bounds")
            }
            if action.isBounded && channel.outputTransform == .identity {
                throw LearningProjectContractValidationError.invalidAction(reason: "bounded-action-uses-identity-transform")
            }
        }
        try validateActionGroups(action)
        try validateActionCouplingRules(action)
    }

    private func validateActionGroups(_ action: LearningProjectActionContract) throws {
        var groupIDs: Set<String> = []
        var parentsByGroupID: [String: String] = [:]
        for group in action.groups {
            let groupID = group.groupID.trimmingCharacters(in: .whitespacesAndNewlines)
            if groupID.isEmpty {
                throw LearningProjectContractValidationError.invalidAction(reason: "empty-action-group-id")
            }
            if groupIDs.contains(groupID) {
                throw LearningProjectContractValidationError.invalidAction(reason: "duplicate-action-group-id")
            }
            if group.channelIndices.isEmpty {
                throw LearningProjectContractValidationError.invalidAction(reason: "empty-action-group")
            }
            var groupChannelIndices: Set<Int> = []
            for index in group.channelIndices {
                if index < 0 || index >= action.channels.count {
                    throw LearningProjectContractValidationError.invalidAction(reason: "action-group-channel-out-of-range")
                }
                if groupChannelIndices.contains(index) {
                    throw LearningProjectContractValidationError.invalidAction(reason: "duplicate-action-group-channel")
                }
                groupChannelIndices.insert(index)
            }
            groupIDs.insert(groupID)
        }

        for group in action.groups {
            let groupID = group.groupID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parentGroupID = group.parentGroupID else { continue }
            let trimmed = parentGroupID.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                throw LearningProjectContractValidationError.invalidAction(reason: "empty-action-group-parent")
            }
            if !groupIDs.contains(trimmed) {
                throw LearningProjectContractValidationError.invalidAction(reason: "unknown-action-group-parent")
            }
            if trimmed == groupID {
                throw LearningProjectContractValidationError.invalidAction(reason: "self-parent-action-group")
            }
            parentsByGroupID[groupID] = trimmed
        }

        for groupID in groupIDs {
            var visited: Set<String> = []
            var current: String? = groupID
            while let candidate = current {
                if visited.contains(candidate) {
                    throw LearningProjectContractValidationError.invalidAction(reason: "cyclic-action-group-parent")
                }
                visited.insert(candidate)
                current = parentsByGroupID[candidate]
            }
        }
    }

    private func validateActionCouplingRules(_ action: LearningProjectActionContract) throws {
        var ruleIDs: Set<String> = []
        let groupIDs = Set(action.groups.map { $0.groupID.trimmingCharacters(in: .whitespacesAndNewlines) })
        for rule in action.couplingRules {
            let ruleID = rule.ruleID.trimmingCharacters(in: .whitespacesAndNewlines)
            if ruleID.isEmpty {
                throw LearningProjectContractValidationError.invalidAction(reason: "empty-action-coupling-rule-id")
            }
            if ruleIDs.contains(ruleID) {
                throw LearningProjectContractValidationError.invalidAction(reason: "duplicate-action-coupling-rule-id")
            }
            let sourceGroupID = rule.sourceGroupID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetGroupID = rule.targetGroupID?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let sourceGroupID {
                if sourceGroupID.isEmpty {
                    throw LearningProjectContractValidationError.invalidAction(reason: "empty-action-coupling-source-group")
                }
                if !groupIDs.contains(sourceGroupID) {
                    throw LearningProjectContractValidationError.invalidAction(reason: "unknown-action-coupling-source-group")
                }
            }
            if let targetGroupID {
                if targetGroupID.isEmpty {
                    throw LearningProjectContractValidationError.invalidAction(reason: "empty-action-coupling-target-group")
                }
                if !groupIDs.contains(targetGroupID) {
                    throw LearningProjectContractValidationError.invalidAction(reason: "unknown-action-coupling-target-group")
                }
            }
            if sourceGroupID == nil && targetGroupID == nil && rule.channelIndices.isEmpty {
                throw LearningProjectContractValidationError.invalidAction(reason: "empty-action-coupling-scope")
            }
            for index in rule.channelIndices {
                if index < 0 || index >= action.channels.count {
                    throw LearningProjectContractValidationError.invalidAction(
                        reason: "action-coupling-channel-out-of-range"
                    )
                }
            }
            if let coefficient = rule.coefficient,
               !coefficient.isFinite {
                throw LearningProjectContractValidationError.invalidAction(reason: "non-finite-action-coupling-coefficient")
            }
            ruleIDs.insert(ruleID)
        }
    }

    public func validatePolicy(
        _ policy: LearningProjectPolicyContract,
        observation: LearningProjectObservationContract,
        action: LearningProjectActionContract
    ) throws {
        try validatePolicy(policy, action: action)
        if policy.temporalWindow.observationDimension != observation.channelCount {
            throw LearningProjectContractValidationError.invalidPolicy(reason: "policy-observation-dimension-mismatch")
        }
    }

    public func validatePolicy(
        _ policy: LearningProjectPolicyContract,
        action: LearningProjectActionContract
    ) throws {
        if policy.actionDimension <= 0 {
            throw LearningProjectContractValidationError.invalidPolicy(reason: "non-positive-action-dimension")
        }
        if policy.temporalWindow.historyLength <= 0 {
            throw LearningProjectContractValidationError.invalidPolicy(reason: "non-positive-history-length")
        }
        if let driveCount = action.driveCount, policy.actionDimension != driveCount {
            throw LearningProjectContractValidationError.invalidPolicy(reason: "policy-action-drive-count-mismatch")
        }
        if policy.actionDimension != action.channels.count {
            throw LearningProjectContractValidationError.invalidPolicy(reason: "policy-action-channel-count-mismatch")
        }
        if policy.actionDistribution == .gaussian && !policy.ppo.isEnabled {
            throw LearningProjectContractValidationError.invalidPolicy(reason: "gaussian-policy-requires-ppo")
        }
        if policy.privilegedCritic.isEnabled {
            if policy.privilegedCritic.privilegedDimension <= 0 {
                throw LearningProjectContractValidationError.invalidPolicy(reason: "privileged-critic-missing-dimension")
            }
            if policy.privilegedCritic.parameterNames.count != policy.privilegedCritic.privilegedDimension {
                throw LearningProjectContractValidationError.invalidPolicy(reason: "privileged-critic-parameter-count-mismatch")
            }
        }
        if policy.ppo.isEnabled {
            if !policy.ppo.clipEpsilon.isFinite || policy.ppo.clipEpsilon <= 0 {
                throw LearningProjectContractValidationError.invalidPolicy(reason: "invalid-ppo-clip-epsilon")
            }
            if !policy.ppo.discount.isFinite || policy.ppo.discount <= 0 || policy.ppo.discount > 1 {
                throw LearningProjectContractValidationError.invalidPolicy(reason: "invalid-ppo-discount")
            }
            if !policy.ppo.gaeLambda.isFinite || policy.ppo.gaeLambda < 0 || policy.ppo.gaeLambda > 1 {
                throw LearningProjectContractValidationError.invalidPolicy(reason: "invalid-ppo-gae-lambda")
            }
            if !policy.ppo.actionSmoothnessCoefficient.isFinite || policy.ppo.actionSmoothnessCoefficient < 0 {
                throw LearningProjectContractValidationError.invalidPolicy(reason: "invalid-action-smoothness-coefficient")
            }
        }
        if policy.domainRandomization.isEnabled {
            if !policy.domainRandomization.maximumWindMetersPerSecond.isFinite ||
                policy.domainRandomization.maximumWindMetersPerSecond < 0 {
                throw LearningProjectContractValidationError.invalidPolicy(reason: "invalid-maximum-wind")
            }
            for parameter in policy.domainRandomization.parameters {
                if parameter.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw LearningProjectContractValidationError.invalidPolicy(reason: "empty-domain-randomization-parameter")
                }
                if !parameter.lowerMultiplier.isFinite || !parameter.upperMultiplier.isFinite ||
                    parameter.lowerMultiplier <= 0 || parameter.upperMultiplier < parameter.lowerMultiplier {
                    throw LearningProjectContractValidationError.invalidPolicy(reason: "invalid-domain-randomization-range")
                }
            }
        }
        if policy.actionSafety.isEnabled {
            if policy.actionSafety.lowerBounds.count != policy.actionDimension ||
                policy.actionSafety.upperBounds.count != policy.actionDimension {
                throw LearningProjectContractValidationError.invalidPolicy(reason: "action-safety-dimension-mismatch")
            }
            for index in 0..<policy.actionDimension {
                let lowerBound = policy.actionSafety.lowerBounds[index]
                let upperBound = policy.actionSafety.upperBounds[index]
                if !lowerBound.isFinite || !upperBound.isFinite || upperBound < lowerBound {
                    throw LearningProjectContractValidationError.invalidPolicy(reason: "invalid-action-safety-bounds")
                }
            }
            if !policy.actionSafety.smoothingAlpha.isFinite ||
                policy.actionSafety.smoothingAlpha < 0 ||
                policy.actionSafety.smoothingAlpha > 1 {
                throw LearningProjectContractValidationError.invalidPolicy(reason: "invalid-action-safety-smoothing-alpha")
            }
        }
    }
}
