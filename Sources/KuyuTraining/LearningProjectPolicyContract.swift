import Foundation

public enum LearningProjectPolicyArchitecture: String, Codable, Sendable, Equatable, CaseIterable {
    case feedForward
    case temporalGRUActorCritic
    case temporalTransformerActorCritic
    case temporalTCNActorCritic
}

public enum LearningProjectPolicyActionEncoding: String, Codable, Sendable, Equatable, CaseIterable {
    case ctbr
    case directMotor
    case jointTargets
    case vehicleSteerThrottleBrake
}

public enum LearningProjectPolicyActionDistribution: String, Codable, Sendable, Equatable, CaseIterable {
    case deterministic
    case gaussian
}

public struct LearningProjectTemporalWindowContract: Codable, Sendable, Equatable {
    public let historyLength: Int
    public let observationDimension: Int
    public let previousActionDimension: Int
    public let targetTrajectoryPointCount: Int

    public init(
        historyLength: Int,
        observationDimension: Int,
        previousActionDimension: Int,
        targetTrajectoryPointCount: Int
    ) {
        self.historyLength = max(1, historyLength)
        self.observationDimension = max(1, observationDimension)
        self.previousActionDimension = max(0, previousActionDimension)
        self.targetTrajectoryPointCount = max(0, targetTrajectoryPointCount)
    }

    public var actorTensorShapeDescription: String {
        "[batch,\(historyLength),\(observationDimension)]"
    }
}

public struct LearningProjectPrivilegedCriticContract: Codable, Sendable, Equatable {
    public let isEnabled: Bool
    public let privilegedDimension: Int
    public let parameterNames: [String]

    public init(isEnabled: Bool, privilegedDimension: Int, parameterNames: [String]) {
        self.isEnabled = isEnabled
        self.privilegedDimension = max(0, privilegedDimension)
        self.parameterNames = parameterNames
    }

    public var criticObservationDimension: Int {
        privilegedDimension
    }
}

public struct LearningProjectPPOContract: Codable, Sendable, Equatable {
    public let isEnabled: Bool
    public let clipEpsilon: Double
    public let discount: Double
    public let gaeLambda: Double
    public let valueLossCoefficient: Double
    public let entropyCoefficient: Double
    public let actionSmoothnessCoefficient: Double
    public let epochCount: Int
    public let minibatchSize: Int

    public init(
        isEnabled: Bool,
        clipEpsilon: Double,
        discount: Double,
        gaeLambda: Double,
        valueLossCoefficient: Double,
        entropyCoefficient: Double,
        actionSmoothnessCoefficient: Double,
        epochCount: Int,
        minibatchSize: Int
    ) {
        self.isEnabled = isEnabled
        self.clipEpsilon = clipEpsilon
        self.discount = discount
        self.gaeLambda = gaeLambda
        self.valueLossCoefficient = valueLossCoefficient
        self.entropyCoefficient = entropyCoefficient
        self.actionSmoothnessCoefficient = actionSmoothnessCoefficient
        self.epochCount = max(1, epochCount)
        self.minibatchSize = max(1, minibatchSize)
    }
}

public struct LearningProjectBehaviorCloningContract: Codable, Sendable, Equatable {
    public let isEnabled: Bool
    public let loss: String
    public let initialCoefficient: Double
    public let finalCoefficient: Double

    public init(isEnabled: Bool, loss: String, initialCoefficient: Double, finalCoefficient: Double) {
        self.isEnabled = isEnabled
        self.loss = loss
        self.initialCoefficient = initialCoefficient
        self.finalCoefficient = finalCoefficient
    }
}

public struct LearningProjectDomainRandomizationParameter: Codable, Sendable, Equatable {
    public let name: String
    public let lowerMultiplier: Double
    public let upperMultiplier: Double

    public init(name: String, lowerMultiplier: Double, upperMultiplier: Double) {
        self.name = name
        self.lowerMultiplier = lowerMultiplier
        self.upperMultiplier = upperMultiplier
    }
}

public struct LearningProjectDomainRandomizationContract: Codable, Sendable, Equatable {
    public let isEnabled: Bool
    public let parameters: [LearningProjectDomainRandomizationParameter]
    public let maximumActionLatencySteps: Int
    public let maximumWindMetersPerSecond: Double

    public init(
        isEnabled: Bool,
        parameters: [LearningProjectDomainRandomizationParameter],
        maximumActionLatencySteps: Int,
        maximumWindMetersPerSecond: Double
    ) {
        self.isEnabled = isEnabled
        self.parameters = parameters
        self.maximumActionLatencySteps = max(0, maximumActionLatencySteps)
        self.maximumWindMetersPerSecond = maximumWindMetersPerSecond
    }
}

public struct LearningProjectSafetyFilterContract: Codable, Sendable, Equatable {
    public let isEnabled: Bool
    public let minimumThrust: Double
    public let maximumThrust: Double
    public let maximumBodyRate: Double
    public let maximumYawRate: Double
    public let maximumTilt: Double
    public let lowPassAlpha: Double

    public init(
        isEnabled: Bool,
        minimumThrust: Double,
        maximumThrust: Double,
        maximumBodyRate: Double,
        maximumYawRate: Double,
        maximumTilt: Double,
        lowPassAlpha: Double
    ) {
        self.isEnabled = isEnabled
        self.minimumThrust = minimumThrust
        self.maximumThrust = maximumThrust
        self.maximumBodyRate = maximumBodyRate
        self.maximumYawRate = maximumYawRate
        self.maximumTilt = maximumTilt
        self.lowPassAlpha = lowPassAlpha
    }
}

public struct LearningProjectPolicyContract: Codable, Sendable, Equatable {
    public let architecture: LearningProjectPolicyArchitecture
    public let actionEncoding: LearningProjectPolicyActionEncoding
    public let actionDistribution: LearningProjectPolicyActionDistribution
    public let actionDimension: Int
    public let temporalWindow: LearningProjectTemporalWindowContract
    public let privilegedCritic: LearningProjectPrivilegedCriticContract
    public let behaviorCloning: LearningProjectBehaviorCloningContract
    public let ppo: LearningProjectPPOContract
    public let domainRandomization: LearningProjectDomainRandomizationContract
    public let safetyFilter: LearningProjectSafetyFilterContract

    public init(
        architecture: LearningProjectPolicyArchitecture,
        actionEncoding: LearningProjectPolicyActionEncoding,
        actionDistribution: LearningProjectPolicyActionDistribution,
        actionDimension: Int,
        temporalWindow: LearningProjectTemporalWindowContract,
        privilegedCritic: LearningProjectPrivilegedCriticContract,
        behaviorCloning: LearningProjectBehaviorCloningContract,
        ppo: LearningProjectPPOContract,
        domainRandomization: LearningProjectDomainRandomizationContract,
        safetyFilter: LearningProjectSafetyFilterContract
    ) {
        self.architecture = architecture
        self.actionEncoding = actionEncoding
        self.actionDistribution = actionDistribution
        self.actionDimension = max(1, actionDimension)
        self.temporalWindow = temporalWindow
        self.privilegedCritic = privilegedCritic
        self.behaviorCloning = behaviorCloning
        self.ppo = ppo
        self.domainRandomization = domainRandomization
        self.safetyFilter = safetyFilter
    }

    public static func referenceQuadrotorTemporalCTBR() -> LearningProjectPolicyContract {
        LearningProjectPolicyContract(
            architecture: .temporalGRUActorCritic,
            actionEncoding: .ctbr,
            actionDistribution: .gaussian,
            actionDimension: 4,
            temporalWindow: LearningProjectTemporalWindowContract(
                historyLength: 32,
                observationDimension: 64,
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
            safetyFilter: LearningProjectSafetyFilterContract(
                isEnabled: true,
                minimumThrust: 0,
                maximumThrust: 1,
                maximumBodyRate: 1,
                maximumYawRate: 1,
                maximumTilt: 0.95,
                lowPassAlpha: 0.35
            )
        )
    }

    public static func simpleFeedForward(
        observationDimension: Int,
        actionDimension: Int,
        actionEncoding: LearningProjectPolicyActionEncoding
    ) -> LearningProjectPolicyContract {
        LearningProjectPolicyContract(
            architecture: .feedForward,
            actionEncoding: actionEncoding,
            actionDistribution: .deterministic,
            actionDimension: actionDimension,
            temporalWindow: LearningProjectTemporalWindowContract(
                historyLength: 1,
                observationDimension: observationDimension,
                previousActionDimension: actionDimension,
                targetTrajectoryPointCount: 0
            ),
            privilegedCritic: LearningProjectPrivilegedCriticContract(
                isEnabled: false,
                privilegedDimension: 0,
                parameterNames: []
            ),
            behaviorCloning: LearningProjectBehaviorCloningContract(
                isEnabled: false,
                loss: "none",
                initialCoefficient: 0,
                finalCoefficient: 0
            ),
            ppo: LearningProjectPPOContract(
                isEnabled: false,
                clipEpsilon: 0.2,
                discount: 0.99,
                gaeLambda: 0.95,
                valueLossCoefficient: 0.5,
                entropyCoefficient: 0,
                actionSmoothnessCoefficient: 0,
                epochCount: 1,
                minibatchSize: 1
            ),
            domainRandomization: LearningProjectDomainRandomizationContract(
                isEnabled: false,
                parameters: [],
                maximumActionLatencySteps: 0,
                maximumWindMetersPerSecond: 0
            ),
            safetyFilter: LearningProjectSafetyFilterContract(
                isEnabled: false,
                minimumThrust: 0,
                maximumThrust: 1,
                maximumBodyRate: 1,
                maximumYawRate: 1,
                maximumTilt: 1,
                lowPassAlpha: 1
            )
        )
    }
}
