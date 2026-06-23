import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public enum ReferenceQuadrotorLearningContracts {
    public static func liftObservationContract() -> LearningProjectObservationContract {
        LearningProjectObservationContract(
            schemaID: "reference-quadrotor-lift-8ch-v1",
            channelCount: 8,
            channels: [
                LearningProjectObservationChannel(index: 0, name: "gyroX", unit: "rad/s", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 1, name: "gyroY", unit: "rad/s", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 2, name: "gyroZ", unit: "rad/s", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 3, name: "accelX", unit: "m/s^2", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 4, name: "accelY", unit: "m/s^2", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 5, name: "accelZ", unit: "m/s^2", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 6, name: "altitudeZ", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 7, name: "verticalVelocityZ", unit: "m/s", isStateChannel: true, isStressable: true)
            ]
        )
    }

    public static func bodyRateObservationContract() -> LearningProjectObservationContract {
        LearningProjectObservationContract(
            schemaID: "reference-quadrotor-body-rate-control-16ch-v1",
            channelCount: 16,
            channels: [
                LearningProjectObservationChannel(index: 0, name: "roll", unit: "rad", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 1, name: "pitch", unit: "rad", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 2, name: "yaw", unit: "rad", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 3, name: "gyroX", unit: "rad/s", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 4, name: "gyroY", unit: "rad/s", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 5, name: "gyroZ", unit: "rad/s", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 6, name: "velocityX", unit: "m/s", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 7, name: "velocityY", unit: "m/s", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 8, name: "velocityZ", unit: "m/s", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 9, name: "targetDeltaX", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 10, name: "targetDeltaY", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 11, name: "targetDeltaZ", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 12, name: "previousCollectiveThrust", unit: "normalized", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 13, name: "previousRollRate", unit: "normalized", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 14, name: "previousPitchRate", unit: "normalized", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 15, name: "previousYawRate", unit: "normalized", isStateChannel: true, isStressable: true)
            ]
        )
    }

    public static func temporalCTBRObservationContract() -> LearningProjectObservationContract {
        let channels: [LearningProjectObservationChannel] = [
            LearningProjectObservationChannel(index: 0, name: "rotationMatrix00", unit: nil, isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 1, name: "rotationMatrix01", unit: nil, isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 2, name: "rotationMatrix02", unit: nil, isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 3, name: "rotationMatrix10", unit: nil, isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 4, name: "rotationMatrix11", unit: nil, isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 5, name: "rotationMatrix12", unit: nil, isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 6, name: "rotationMatrix20", unit: nil, isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 7, name: "rotationMatrix21", unit: nil, isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 8, name: "rotationMatrix22", unit: nil, isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 9, name: "gyroX", unit: "rad/s", isStateChannel: false, isStressable: true),
            LearningProjectObservationChannel(index: 10, name: "gyroY", unit: "rad/s", isStateChannel: false, isStressable: true),
            LearningProjectObservationChannel(index: 11, name: "gyroZ", unit: "rad/s", isStateChannel: false, isStressable: true),
            LearningProjectObservationChannel(index: 12, name: "velocityX", unit: "m/s", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 13, name: "velocityY", unit: "m/s", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 14, name: "velocityZ", unit: "m/s", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 15, name: "target0DeltaX", unit: "m", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 16, name: "target0DeltaY", unit: "m", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 17, name: "target0DeltaZ", unit: "m", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 18, name: "target1DeltaX", unit: "m", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 19, name: "target1DeltaY", unit: "m", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 20, name: "target1DeltaZ", unit: "m", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 21, name: "target2DeltaX", unit: "m", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 22, name: "target2DeltaY", unit: "m", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 23, name: "target2DeltaZ", unit: "m", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 24, name: "target3DeltaX", unit: "m", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 25, name: "target3DeltaY", unit: "m", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 26, name: "target3DeltaZ", unit: "m", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 27, name: "positionErrorX", unit: "m", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 28, name: "positionErrorY", unit: "m", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 29, name: "positionErrorZ", unit: "m", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 30, name: "velocityErrorX", unit: "m/s", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 31, name: "velocityErrorY", unit: "m/s", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 32, name: "velocityErrorZ", unit: "m/s", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 33, name: "previousCollectiveThrust", unit: "normalized", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 34, name: "previousRollRate", unit: "normalized", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 35, name: "previousPitchRate", unit: "normalized", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 36, name: "previousYawRate", unit: "normalized", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 37, name: "phase", unit: "normalized", isStateChannel: true, isStressable: false),
            LearningProjectObservationChannel(index: 38, name: "altitudeZ", unit: "m", isStateChannel: true, isStressable: true),
            LearningProjectObservationChannel(index: 39, name: "verticalVelocityZ", unit: "m/s", isStateChannel: true, isStressable: true)
        ]
        let reserved = (40..<64).map { index in
            LearningProjectObservationChannel(
                index: index,
                name: "reservedFeature\(index - 40)",
                unit: nil,
                isStateChannel: false,
                isStressable: false
            )
        }
        return LearningProjectObservationContract(
            schemaID: "reference-quadrotor-temporal-ctbr-64ch-v1",
            channelCount: 64,
            channels: channels + reserved
        )
    }

    public static func bodyRateActionContract() -> LearningProjectActionContract {
        LearningProjectActionContract(
            schemaID: "reference-quadrotor-body-rate-control-action-v1",
            kind: .continuous,
            driveCount: 4,
            actuatorCount: 4,
            isBounded: true,
            channels: [
                LearningProjectActionChannel(
                    index: 0,
                    name: "collectiveThrust",
                    unit: "normalized",
                    normalizedLowerBound: 0,
                    normalizedUpperBound: 1,
                    outputTransform: .sigmoid
                ),
                LearningProjectActionChannel(
                    index: 1,
                    name: "bodyRateX",
                    unit: "normalized",
                    normalizedLowerBound: -1,
                    normalizedUpperBound: 1,
                    outputTransform: .tanh
                ),
                LearningProjectActionChannel(
                    index: 2,
                    name: "bodyRateY",
                    unit: "normalized",
                    normalizedLowerBound: -1,
                    normalizedUpperBound: 1,
                    outputTransform: .tanh
                ),
                LearningProjectActionChannel(
                    index: 3,
                    name: "bodyRateZ",
                    unit: "normalized",
                    normalizedLowerBound: -1,
                    normalizedUpperBound: 1,
                    outputTransform: .tanh
                )
            ]
        )
    }

    public static func temporalCTBRPolicyContract(
        observationDimension: Int = 64,
        historyLength: Int = 32
    ) -> LearningProjectPolicyContract {
        LearningProjectPolicyContract(
            architecture: .temporalGRUActorCritic,
            actionEncoding: .ctbr,
            actionDistribution: .gaussian,
            actionDimension: 4,
            temporalWindow: LearningProjectTemporalWindowContract(
                historyLength: historyLength,
                observationDimension: observationDimension,
                previousActionDimension: 4,
                targetTrajectoryPointCount: 4
            ),
            privilegedCritic: LearningProjectPrivilegedCriticContract(
                isEnabled: true,
                privilegedDimension: 13,
                parameterNames: [
                    "mass",
                    "inertiaXX",
                    "inertiaYY",
                    "inertiaZZ",
                    "thrustToWeight",
                    "motorDelay",
                    "dragX",
                    "dragY",
                    "dragZ",
                    "batteryVoltageScale",
                    "windX",
                    "windY",
                    "windZ"
                ]
            ),
            behaviorCloning: LearningProjectBehaviorCloningContract(
                isEnabled: true,
                loss: "mean-squared-ctbr",
                initialCoefficient: 1,
                finalCoefficient: 0.05
            ),
            ppo: LearningProjectPPOContract(
                isEnabled: true,
                clipEpsilon: 0.2,
                discount: 0.997,
                gaeLambda: 0.95,
                valueLossCoefficient: 0.5,
                entropyCoefficient: 0.01,
                actionSmoothnessCoefficient: 0.02,
                epochCount: 4,
                minibatchSize: 256
            ),
            domainRandomization: LearningProjectDomainRandomizationContract(
                isEnabled: true,
                parameters: [
                    LearningProjectDomainRandomizationParameter(name: "mass", lowerMultiplier: 0.85, upperMultiplier: 1.15),
                    LearningProjectDomainRandomizationParameter(name: "inertia", lowerMultiplier: 0.8, upperMultiplier: 1.2),
                    LearningProjectDomainRandomizationParameter(name: "motorTimeConstant", lowerMultiplier: 0.5, upperMultiplier: 1.8),
                    LearningProjectDomainRandomizationParameter(name: "thrustScale", lowerMultiplier: 0.75, upperMultiplier: 1.25),
                    LearningProjectDomainRandomizationParameter(name: "drag", lowerMultiplier: 0.5, upperMultiplier: 1.5),
                    LearningProjectDomainRandomizationParameter(name: "batteryScale", lowerMultiplier: 0.85, upperMultiplier: 1.05)
                ],
                maximumActionLatencySteps: 3,
                maximumWindMetersPerSecond: 3
            ),
            actionSafety: LearningProjectActionSafetyContract(
                isEnabled: true,
                lowerBounds: [0, -1, -1, -1],
                upperBounds: [1, 1, 1, 1],
                smoothingAlpha: 0.35
            )
        )
    }
}
