public struct KuyuControlTransition: Sendable, Codable, Equatable {
    public struct Observation: Sendable, Codable, Equatable {
        public let time: Double
        public let values: [Double]

        public init(time: Double, values: [Double]) {
            self.time = time
            self.values = values
        }
    }

    public struct StateFacts: Sendable, Codable, Equatable {
        public let values: [Double]

        public init(values: [Double]) {
            self.values = values
        }
    }

    public struct PolicyAction: Sendable, Codable, Equatable {
        public let values: [Double]

        public init(values: [Double]) {
            self.values = values
        }
    }

    public struct DriveIntent: Sendable, Codable, Equatable {
        public let driveIndex: Int
        public let activation: Double
        public let parameters: [Double]

        public init(driveIndex: Int, activation: Double, parameters: [Double] = []) {
            self.driveIndex = driveIndex
            self.activation = activation
            self.parameters = parameters
        }
    }

    public struct ReflexCorrection: Sendable, Codable, Equatable {
        public let driveIndex: Int
        public let clamp: Double
        public let damping: Double
        public let delta: Double

        public init(driveIndex: Int, clamp: Double, damping: Double, delta: Double) {
            self.driveIndex = driveIndex
            self.clamp = clamp
            self.damping = damping
            self.delta = delta
        }
    }

    public struct RealizedControl: Sendable, Codable, Equatable {
        public let driveIntents: [DriveIntent]
        public let reflexCorrections: [ReflexCorrection]

        public init(driveIntents: [DriveIntent], reflexCorrections: [ReflexCorrection]) {
            self.driveIntents = driveIntents
            self.reflexCorrections = reflexCorrections
        }
    }

    public struct ActuatorCommand: Sendable, Codable, Equatable {
        public let values: [Double]

        public init(values: [Double]) {
            self.values = values
        }
    }

    public let coordinate: KuyuTrajectoryCoordinate
    public let sourceObservation: Observation
    public let sourceStateFacts: StateFacts
    public let policyAction: PolicyAction
    public let realizedControl: RealizedControl
    public let actuatorCommand: ActuatorCommand
    public let outcomeObservation: Observation
    public let outcomeStateFacts: StateFacts
    public let reward: Double
    public let safetyCost: Double
    public let interval: KuyuControlInterval
    public let boundary: KuyuTrajectoryBoundary

    public init(
        coordinate: KuyuTrajectoryCoordinate,
        sourceObservation: Observation,
        sourceStateFacts: StateFacts,
        policyAction: PolicyAction,
        realizedControl: RealizedControl,
        actuatorCommand: ActuatorCommand,
        outcomeObservation: Observation,
        outcomeStateFacts: StateFacts,
        reward: Double,
        safetyCost: Double,
        interval: KuyuControlInterval,
        boundary: KuyuTrajectoryBoundary
    ) {
        self.coordinate = coordinate
        self.sourceObservation = sourceObservation
        self.sourceStateFacts = sourceStateFacts
        self.policyAction = policyAction
        self.realizedControl = realizedControl
        self.actuatorCommand = actuatorCommand
        self.outcomeObservation = outcomeObservation
        self.outcomeStateFacts = outcomeStateFacts
        self.reward = reward
        self.safetyCost = safetyCost
        self.interval = interval
        self.boundary = boundary
    }
}
