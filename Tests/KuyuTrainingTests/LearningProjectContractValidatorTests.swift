import KuyuTraining
import Testing

@Test func learningProjectContractValidatorRejectsNonFiniteActionSafetySmoothing() throws {
    let action = ReferenceQuadrotorLearningContracts.bodyRateActionContract()
    let base = ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract()
    let policy = LearningProjectPolicyContract(
        architecture: base.architecture,
        actionEncoding: base.actionEncoding,
        actionDistribution: base.actionDistribution,
        actionDimension: base.actionDimension,
        temporalWindow: base.temporalWindow,
        privilegedCritic: base.privilegedCritic,
        behaviorCloning: base.behaviorCloning,
        ppo: base.ppo,
        domainRandomization: base.domainRandomization,
        actionSafety: LearningProjectActionSafetyContract(
            isEnabled: true,
            lowerBounds: base.actionSafety.lowerBounds,
            upperBounds: base.actionSafety.upperBounds,
            smoothingAlpha: .nan
        )
    )

    do {
        try LearningProjectContractValidator().validatePolicy(policy, action: action)
        Issue.record("Expected non-finite smoothing alpha to throw.")
    } catch LearningProjectContractValidationError.invalidPolicy(let reason) {
        #expect(reason == "invalid-action-safety-smoothing-alpha")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func learningProjectContractValidatorRejectsGaussianDistributionDimensionMismatch() throws {
    let action = ReferenceQuadrotorLearningContracts.bodyRateActionContract()
    let base = ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract()
    let policy = policy(
        base,
        replacing: .fixedGaussian(actionDimension: base.actionDimension - 1)
    )

    do {
        try LearningProjectContractValidator().validatePolicy(policy, action: action)
        Issue.record("Expected distribution dimension mismatch to throw.")
    } catch LearningProjectContractValidationError.invalidPolicy(let reason) {
        #expect(reason == "gaussian-log-standard-deviation-dimension-mismatch")
    }
}

@Test func learningProjectContractValidatorRejectsPreviousActionDimensionMismatch() throws {
    let action = ReferenceQuadrotorLearningContracts.bodyRateActionContract()
    let base = ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract()
    let policy = LearningProjectPolicyContract(
        architecture: base.architecture,
        actionEncoding: base.actionEncoding,
        actionDistribution: base.actionDistribution,
        actionDimension: base.actionDimension,
        temporalWindow: LearningProjectTemporalWindowContract(
            historyLength: base.temporalWindow.historyLength,
            observationDimension: base.temporalWindow.observationDimension,
            previousActionDimension: base.actionDimension - 1,
            targetTrajectoryPointCount: base.temporalWindow.targetTrajectoryPointCount,
            execution: base.temporalWindow.execution
        ),
        privilegedCritic: base.privilegedCritic,
        behaviorCloning: base.behaviorCloning,
        ppo: base.ppo,
        domainRandomization: base.domainRandomization,
        actionSafety: base.actionSafety
    )

    do {
        try LearningProjectContractValidator().validatePolicy(policy, action: action)
        Issue.record("Expected previous-action dimension mismatch to throw.")
    } catch LearningProjectContractValidationError.invalidPolicy(let reason) {
        #expect(reason == "policy-previous-action-dimension-mismatch")
    }
}

@Test func learningProjectContractValidatorRejectsUnknownGaussianDensityContract() throws {
    let action = ReferenceQuadrotorLearningContracts.bodyRateActionContract()
    let base = ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract()
    let policy = policy(
        base,
        replacing: LearningProjectPolicyActionDistributionContract(
            kind: .gaussian,
            densityContractID: "unknown-density-v1",
            baseLogStandardDeviations: Array(repeating: -3.2, count: base.actionDimension)
        )
    )

    do {
        try LearningProjectContractValidator().validatePolicy(policy, action: action)
        Issue.record("Expected unknown density contract to throw.")
    } catch LearningProjectContractValidationError.invalidPolicy(let reason) {
        #expect(reason == "unsupported-gaussian-density-contract")
    }
}

@Test func learningProjectContractValidatorRejectsGaussianClampedLinearAction() throws {
    let base = ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract()
    let action = LearningProjectActionContract(
        schemaID: "clamped-ctbr-v1",
        kind: .continuous,
        driveCount: base.actionDimension,
        actuatorCount: base.actionDimension,
        isBounded: true,
        channels: LearningProjectActionContract.indexedBoundedChannels(
            prefix: "drive",
            count: base.actionDimension,
            unit: "normalized",
            lowerBound: -1,
            upperBound: 1,
            transform: .clampedLinear
        )
    )

    do {
        try LearningProjectContractValidator().validatePolicy(base, action: action)
        Issue.record("Expected non-invertible Gaussian action transform to throw.")
    } catch LearningProjectContractValidationError.invalidPolicy(let reason) {
        #expect(reason == "gaussian-policy-requires-invertible-action-transform")
    }
}

@Test func learningProjectContractValidatorAcceptsHumanoidScaleActionGroups() throws {
    let channelCount = 128
    let action = LearningProjectActionContract(
        schemaID: "humanoid-drive-intent-v1",
        kind: .continuous,
        driveCount: channelCount,
        actuatorCount: 128,
        isBounded: true,
        channels: LearningProjectActionContract.indexedBoundedChannels(
            prefix: "drive",
            count: channelCount,
            unit: "normalized",
            lowerBound: -1,
            upperBound: 1,
            transform: .tanh
        ),
        groups: [
            LearningProjectActionGroup(
                groupID: "left-leg",
                channelIndices: Array(0..<24),
                role: .bodyPart
            ),
            LearningProjectActionGroup(
                groupID: "right-leg",
                channelIndices: Array(24..<48),
                role: .bodyPart
            ),
            LearningProjectActionGroup(
                groupID: "torso-balance",
                channelIndices: Array(48..<64),
                role: .stabilizer
            ),
            LearningProjectActionGroup(
                groupID: "left-arm",
                channelIndices: Array(64..<88),
                role: .bodyPart
            ),
            LearningProjectActionGroup(
                groupID: "right-arm",
                channelIndices: Array(88..<112),
                role: .bodyPart
            ),
            LearningProjectActionGroup(
                groupID: "hands",
                channelIndices: Array(112..<128),
                role: .synergy
            )
        ],
        couplingRules: [
            LearningProjectActionCouplingRule(
                ruleID: "leg-antiphase",
                kind: .antiSymmetric,
                sourceGroupID: "left-leg",
                targetGroupID: "right-leg",
                coefficient: 1
            ),
            LearningProjectActionCouplingRule(
                ruleID: "arm-symmetry",
                kind: .symmetric,
                sourceGroupID: "left-arm",
                targetGroupID: "right-arm",
                coefficient: 0.5
            )
        ]
    )

    try LearningProjectContractValidator().validateAction(action)
}

@Test func learningProjectContractValidatorRejectsInvalidActionGroupChannelIndex() throws {
    let action = LearningProjectActionContract(
        schemaID: "invalid-group-v1",
        kind: .continuous,
        driveCount: 2,
        actuatorCount: 2,
        isBounded: true,
        channels: LearningProjectActionContract.indexedBoundedChannels(
            prefix: "drive",
            count: 2,
            unit: "normalized",
            lowerBound: -1,
            upperBound: 1,
            transform: .tanh
        ),
        groups: [
            LearningProjectActionGroup(
                groupID: "bad-group",
                channelIndices: [0, 2],
                role: .bodyPart
            )
        ]
    )

    do {
        try LearningProjectContractValidator().validateAction(action)
        Issue.record("Expected invalid action group channel index to throw.")
    } catch LearningProjectContractValidationError.invalidAction(let reason) {
        #expect(reason == "action-group-channel-out-of-range")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func learningProjectContractValidatorRejectsCyclicActionGroupParent() throws {
    let action = LearningProjectActionContract(
        schemaID: "cyclic-group-v1",
        kind: .continuous,
        driveCount: 4,
        actuatorCount: 4,
        isBounded: true,
        channels: LearningProjectActionContract.indexedBoundedChannels(
            prefix: "drive",
            count: 4,
            unit: "normalized",
            lowerBound: -1,
            upperBound: 1,
            transform: .tanh
        ),
        groups: [
            LearningProjectActionGroup(
                groupID: "left",
                channelIndices: [0, 1],
                parentGroupID: "right",
                role: .bodyPart
            ),
            LearningProjectActionGroup(
                groupID: "right",
                channelIndices: [2, 3],
                parentGroupID: "left",
                role: .bodyPart
            )
        ]
    )

    do {
        try LearningProjectContractValidator().validateAction(action)
        Issue.record("Expected cyclic action group parent to throw.")
    } catch LearningProjectContractValidationError.invalidAction(let reason) {
        #expect(reason == "cyclic-action-group-parent")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func learningProjectContractValidatorRejectsDuplicateActionGroupChannel() throws {
    let action = LearningProjectActionContract(
        schemaID: "duplicate-group-channel-v1",
        kind: .continuous,
        driveCount: 2,
        actuatorCount: 2,
        isBounded: true,
        channels: LearningProjectActionContract.indexedBoundedChannels(
            prefix: "drive",
            count: 2,
            unit: "normalized",
            lowerBound: -1,
            upperBound: 1,
            transform: .tanh
        ),
        groups: [
            LearningProjectActionGroup(
                groupID: "bad-group",
                channelIndices: [0, 0],
                role: .bodyPart
            )
        ]
    )

    do {
        try LearningProjectContractValidator().validateAction(action)
        Issue.record("Expected duplicate action group channel to throw.")
    } catch LearningProjectContractValidationError.invalidAction(let reason) {
        #expect(reason == "duplicate-action-group-channel")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func learningProjectContractValidatorRejectsEmptyActionCouplingScope() throws {
    let action = LearningProjectActionContract(
        schemaID: "empty-coupling-scope-v1",
        kind: .continuous,
        driveCount: 2,
        actuatorCount: 2,
        isBounded: true,
        channels: LearningProjectActionContract.indexedBoundedChannels(
            prefix: "drive",
            count: 2,
            unit: "normalized",
            lowerBound: -1,
            upperBound: 1,
            transform: .tanh
        ),
        couplingRules: [
            LearningProjectActionCouplingRule(
                ruleID: "empty-rule",
                kind: .custom
            )
        ]
    )

    do {
        try LearningProjectContractValidator().validateAction(action)
        Issue.record("Expected empty action coupling scope to throw.")
    } catch LearningProjectContractValidationError.invalidAction(let reason) {
        #expect(reason == "empty-action-coupling-scope")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

private func policy(
    _ base: LearningProjectPolicyContract,
    replacing actionDistribution: LearningProjectPolicyActionDistributionContract
) -> LearningProjectPolicyContract {
    LearningProjectPolicyContract(
        architecture: base.architecture,
        actionEncoding: base.actionEncoding,
        actionDistribution: actionDistribution,
        actionDimension: base.actionDimension,
        temporalWindow: base.temporalWindow,
        privilegedCritic: base.privilegedCritic,
        behaviorCloning: base.behaviorCloning,
        ppo: base.ppo,
        domainRandomization: base.domainRandomization,
        actionSafety: base.actionSafety
    )
}
