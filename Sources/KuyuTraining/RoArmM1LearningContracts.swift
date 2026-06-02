import Foundation

public enum RoArmM1LearningContracts {
    public static func armGripperTargetTrackingObservationContract() -> LearningProjectObservationContract {
        let channelNames = RoArmM1ArmGripperSemantics.observationChannelNames
        return LearningProjectObservationContract(
            schemaID: RoArmM1JointTargetTrainingGoal.canonical.observationSchemaID,
            channelCount: channelNames.count,
            channels: channelNames.enumerated().map { index, name in
                let isTargetError = name.hasSuffix("TargetError")
                return LearningProjectObservationChannel(
                    index: index,
                    name: name,
                    unit: isTargetError ? "rad" : unit(forArmGripperChannel: name),
                    isStateChannel: true,
                    isStressable: !isTargetError
                )
            }
        )
    }

    public static func armGripperTargetsActionContract() -> LearningProjectActionContract {
        LearningProjectActionContract(
            schemaID: RoArmM1JointTargetTrainingGoal.canonical.actionSchemaID,
            kind: .continuous,
            driveCount: 5,
            actuatorCount: 5,
            isBounded: true,
            channels: LearningProjectActionContract.boundedChannels(
                names: RoArmM1ArmGripperSemantics.driveIDs,
                unit: "normalized",
                lowerBound: -1,
                upperBound: 1,
                transform: .tanh
            )
        )
    }

    public static func armGripperTargetTrackingPolicyContract() -> LearningProjectPolicyContract {
        LearningProjectPolicyContract(
            architecture: .feedForward,
            actionEncoding: .jointTargets,
            actionDistribution: .deterministic,
            actionDimension: 5,
            temporalWindow: LearningProjectTemporalWindowContract(
                historyLength: 1,
                observationDimension: 25,
                previousActionDimension: 5,
                targetTrajectoryPointCount: 1
            ),
            privilegedCritic: LearningProjectPrivilegedCriticContract(
                isEnabled: false,
                privilegedDimension: 0,
                parameterNames: []
            ),
            behaviorCloning: LearningProjectBehaviorCloningContract(
                isEnabled: true,
                loss: "mean-squared-arm-gripper-target",
                initialCoefficient: 1,
                finalCoefficient: 0.2
            ),
            ppo: LearningProjectPPOContract(
                isEnabled: false,
                clipEpsilon: 0.2,
                discount: 0.99,
                gaeLambda: 0.95,
                valueLossCoefficient: 0.5,
                entropyCoefficient: 0,
                actionSmoothnessCoefficient: 0.01,
                epochCount: 1,
                minibatchSize: 1
            ),
            domainRandomization: LearningProjectDomainRandomizationContract(
                isEnabled: true,
                parameters: [
                    LearningProjectDomainRandomizationParameter(name: "linkMass", lowerMultiplier: 0.85, upperMultiplier: 1.15),
                    LearningProjectDomainRandomizationParameter(name: "linkInertia", lowerMultiplier: 0.8, upperMultiplier: 1.2),
                    LearningProjectDomainRandomizationParameter(name: "servoTimeConstant", lowerMultiplier: 0.6, upperMultiplier: 1.6),
                    LearningProjectDomainRandomizationParameter(name: "servoTorqueLimit", lowerMultiplier: 0.75, upperMultiplier: 1.1),
                    LearningProjectDomainRandomizationParameter(name: "jointDamping", lowerMultiplier: 0.5, upperMultiplier: 1.5),
                    LearningProjectDomainRandomizationParameter(name: "coulombFriction", lowerMultiplier: 0.5, upperMultiplier: 1.8)
                ],
                maximumActionLatencySteps: 2,
                maximumWindMetersPerSecond: 0
            ),
            actionSafety: LearningProjectActionSafetyContract(
                isEnabled: false,
                lowerBounds: Array(repeating: -1, count: 5),
                upperBounds: Array(repeating: 1, count: 5),
                smoothingAlpha: 1
            )
        )
    }

    private static func unit(forArmGripperChannel name: String) -> String? {
        if name.hasSuffix("Position") || name.hasSuffix("LowerLimitMargin") || name.hasSuffix("UpperLimitMargin") {
            return "rad"
        }
        if name.hasSuffix("Velocity") {
            return "rad/s"
        }
        return nil
    }
}
