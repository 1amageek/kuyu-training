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

public struct LearningProjectTemporalWindowContract: Codable, Sendable, Equatable {
    public let historyLength: Int
    public let observationDimension: Int
    public let previousActionDimension: Int
    public let targetTrajectoryPointCount: Int
    public let execution: LearningProjectTemporalExecutionContract

    public init(
        historyLength: Int,
        observationDimension: Int,
        previousActionDimension: Int,
        targetTrajectoryPointCount: Int,
        execution: LearningProjectTemporalExecutionContract = .fixedWindowZeroState
    ) {
        self.historyLength = max(1, historyLength)
        self.observationDimension = max(1, observationDimension)
        self.previousActionDimension = max(0, previousActionDimension)
        self.targetTrajectoryPointCount = max(0, targetTrajectoryPointCount)
        self.execution = execution
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
    public let actionSmoothnessCoefficient: Double
    public let entropyRegularization: LearningProjectPPOEntropyRegularization
    public let epochCount: Int
    public let minibatchSize: Int

    public init(
        isEnabled: Bool,
        clipEpsilon: Double,
        discount: Double,
        gaeLambda: Double,
        valueLossCoefficient: Double,
        actionSmoothnessCoefficient: Double,
        entropyRegularization: LearningProjectPPOEntropyRegularization = .none,
        epochCount: Int,
        minibatchSize: Int
    ) {
        self.isEnabled = isEnabled
        self.clipEpsilon = clipEpsilon
        self.discount = discount
        self.gaeLambda = gaeLambda
        self.valueLossCoefficient = valueLossCoefficient
        self.actionSmoothnessCoefficient = actionSmoothnessCoefficient
        self.entropyRegularization = entropyRegularization
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

public struct LearningProjectActionSafetyContract: Codable, Sendable, Equatable {
    public let isEnabled: Bool
    public let lowerBounds: [Double]
    public let upperBounds: [Double]
    public let smoothingAlpha: Double

    public init(
        isEnabled: Bool,
        lowerBounds: [Double],
        upperBounds: [Double],
        smoothingAlpha: Double
    ) {
        self.isEnabled = isEnabled
        self.lowerBounds = lowerBounds
        self.upperBounds = upperBounds
        self.smoothingAlpha = smoothingAlpha
    }
}

public struct LearningProjectPolicyContract: Codable, Sendable, Equatable {
    public let architecture: LearningProjectPolicyArchitecture
    public let actionEncoding: LearningProjectPolicyActionEncoding
    public let actionDistribution: LearningProjectPolicyActionDistributionContract
    public let actionDimension: Int
    public let temporalWindow: LearningProjectTemporalWindowContract
    public let privilegedCritic: LearningProjectPrivilegedCriticContract
    public let behaviorCloning: LearningProjectBehaviorCloningContract
    public let ppo: LearningProjectPPOContract
    public let domainRandomization: LearningProjectDomainRandomizationContract
    public let actionSafety: LearningProjectActionSafetyContract

    public init(
        architecture: LearningProjectPolicyArchitecture,
        actionEncoding: LearningProjectPolicyActionEncoding,
        actionDistribution: LearningProjectPolicyActionDistributionContract,
        actionDimension: Int,
        temporalWindow: LearningProjectTemporalWindowContract,
        privilegedCritic: LearningProjectPrivilegedCriticContract,
        behaviorCloning: LearningProjectBehaviorCloningContract,
        ppo: LearningProjectPPOContract,
        domainRandomization: LearningProjectDomainRandomizationContract,
        actionSafety: LearningProjectActionSafetyContract
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
        self.actionSafety = actionSafety
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
            actionSafety: LearningProjectActionSafetyContract(
                isEnabled: false,
                lowerBounds: Array(repeating: -1, count: actionDimension),
                upperBounds: Array(repeating: 1, count: actionDimension),
                smoothingAlpha: 1
            )
        )
    }
}
