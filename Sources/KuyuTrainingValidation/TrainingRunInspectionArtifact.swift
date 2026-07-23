import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios

/// Compact, durable replay evidence produced from a checkpoint evaluation.
///
/// Samples are display-oriented projections of the authoritative full-step
/// rollout. Evaluation and acceptance always use the unsampled rollout.
public struct TrainingRunInspectionArtifact: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 3
    public static let fileName = "training-inspection.json"
    public static let artifactKind = "training-inspection"

    public enum Origin: String, Sendable, Codable, Equatable {
        case trainingIteration
        case derivedReevaluation
    }

    public enum CheckpointRole: String, Sendable, Codable, Equatable {
        case retained
        case candidate
    }

    public struct MetricDescriptor: Sendable, Codable, Equatable {
        public let id: String
        public let version: String
        public let configHash: String

        public init(id: String, version: String, configHash: String) {
            self.id = id
            self.version = version
            self.configHash = configHash
        }
    }

    public struct ExecutionDescriptor: Sendable, Codable, Equatable {
        public let actionContractSchemaID: String
        public let actionRealization: ReferenceQuadrotorActionRealization
        public let parameters: ReferenceQuadrotorParameters
        public let schedule: SimulationSchedule
        public let determinism: DeterminismConfig
        public let robotManifestID: String?
        public let motorNerveSettings: TaskMotorNerveSettings

        public init(
            actionContractSchemaID: String,
            actionRealization: ReferenceQuadrotorActionRealization,
            parameters: ReferenceQuadrotorParameters,
            schedule: SimulationSchedule,
            determinism: DeterminismConfig,
            robotManifestID: String?,
            motorNerveSettings: TaskMotorNerveSettings
        ) {
            self.actionContractSchemaID = actionContractSchemaID
            self.actionRealization = actionRealization
            self.parameters = parameters
            self.schedule = schedule
            self.determinism = determinism
            self.robotManifestID = robotManifestID
            self.motorNerveSettings = motorNerveSettings
        }
    }

    public struct Sample: Sendable, Codable, Equatable {
        public let step: WorldStepLog
        public let safetyCost: Double?
        public let constraintViolationIDs: [String]

        public init(
            step: WorldStepLog,
            safetyCost: Double?,
            constraintViolationIDs: [String] = []
        ) {
            self.step = step
            self.safetyCost = safetyCost
            self.constraintViolationIDs = constraintViolationIDs
        }
    }

    public struct Scenario: Sendable, Codable, Equatable {
        public let scenarioID: String
        public let seed: UInt64
        public let configHash: String
        public let passed: Bool
        public let failureReason: String?
        public let failureTime: Double?
        public let sourceStepCount: Int
        public let sourceTimeStep: Double
        public let sourcePhysicsTimeStep: Double
        public let sourceControlPeriodSteps: UInt64
        public let samples: [Sample]

        public init(
            scenarioID: String,
            seed: UInt64,
            configHash: String,
            passed: Bool,
            failureReason: String?,
            failureTime: Double?,
            sourceStepCount: Int,
            sourceTimeStep: Double,
            sourcePhysicsTimeStep: Double,
            sourceControlPeriodSteps: UInt64,
            samples: [Sample]
        ) {
            self.scenarioID = scenarioID
            self.seed = seed
            self.configHash = configHash
            self.passed = passed
            self.failureReason = failureReason
            self.failureTime = failureTime
            self.sourceStepCount = sourceStepCount
            self.sourceTimeStep = sourceTimeStep
            self.sourcePhysicsTimeStep = sourcePhysicsTimeStep
            self.sourceControlPeriodSteps = sourceControlPeriodSteps
            self.samples = samples
        }

        public var identity: String {
            "\(scenarioID)#\(seed)"
        }
    }

    public let schemaVersion: Int
    public let runID: String
    public let origin: Origin
    public let iteration: Int?
    public let candidateID: String
    public let checkpointPath: String
    public let checkpointDigest: String?
    public let checkpointRole: CheckpointRole
    public let profile: TaskEvaluationProfile
    public let execution: ExecutionDescriptor
    public let generatedAt: Date
    public let targetSampleRateHz: Double
    public let safetyCostDescriptor: MetricDescriptor?
    public let scenarios: [Scenario]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        runID: String,
        origin: Origin,
        iteration: Int? = nil,
        candidateID: String,
        checkpointPath: String,
        checkpointDigest: String? = nil,
        checkpointRole: CheckpointRole,
        profile: TaskEvaluationProfile,
        execution: ExecutionDescriptor,
        generatedAt: Date = Date(),
        targetSampleRateHz: Double,
        safetyCostDescriptor: MetricDescriptor? = nil,
        scenarios: [Scenario]
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.origin = origin
        self.iteration = iteration
        self.candidateID = candidateID
        self.checkpointPath = checkpointPath
        self.checkpointDigest = checkpointDigest
        self.checkpointRole = checkpointRole
        self.profile = profile
        self.execution = execution
        self.generatedAt = generatedAt
        self.targetSampleRateHz = targetSampleRateHz
        self.safetyCostDescriptor = safetyCostDescriptor
        self.scenarios = scenarios
    }

    public var profileID: String {
        profile.profileID
    }
}
