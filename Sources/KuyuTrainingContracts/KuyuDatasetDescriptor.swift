import Foundation

public struct KuyuDatasetDescriptor: Sendable, Codable, Equatable {
    public struct Identity: Sendable, Codable, Equatable {
        public let datasetID: String
        public let scenarioID: String
        public let scenarioRevision: String
        public let suiteID: String
        public let suiteVersion: String
        public let seed: UInt64
        public let episodeID: String
        public let segmentID: String
        public let segmentIndex: Int

        public init(
            datasetID: String,
            scenarioID: String,
            scenarioRevision: String,
            suiteID: String,
            suiteVersion: String,
            seed: UInt64,
            episodeID: String,
            segmentID: String,
            segmentIndex: Int
        ) {
            self.datasetID = datasetID
            self.scenarioID = scenarioID
            self.scenarioRevision = scenarioRevision
            self.suiteID = suiteID
            self.suiteVersion = suiteVersion
            self.seed = seed
            self.episodeID = episodeID
            self.segmentID = segmentID
            self.segmentIndex = segmentIndex
        }
    }

    public struct Producer: Sendable, Codable, Equatable {
        public let id: String
        public let version: String

        public init(id: String, version: String) {
            self.id = id
            self.version = version
        }
    }

    public struct Execution: Sendable, Codable, Equatable {
        public let dynamicsProgramSchemaVersion: Int
        public let dynamicsProgramDigest: String
        public let fidelityID: String
        public let constraintProjectionID: String
        public let mixerID: String
        public let rotorSpinConventionID: String
        public let backendID: String
        public let backendVersion: String
        public let numericType: String
        public let deviceClass: String
        public let determinismTier: String

        public init(
            dynamicsProgramSchemaVersion: Int,
            dynamicsProgramDigest: String,
            fidelityID: String,
            constraintProjectionID: String,
            mixerID: String,
            rotorSpinConventionID: String,
            backendID: String,
            backendVersion: String,
            numericType: String,
            deviceClass: String,
            determinismTier: String
        ) {
            self.dynamicsProgramSchemaVersion = dynamicsProgramSchemaVersion
            self.dynamicsProgramDigest = dynamicsProgramDigest
            self.fidelityID = fidelityID
            self.constraintProjectionID = constraintProjectionID
            self.mixerID = mixerID
            self.rotorSpinConventionID = rotorSpinConventionID
            self.backendID = backendID
            self.backendVersion = backendVersion
            self.numericType = numericType
            self.deviceClass = deviceClass
            self.determinismTier = determinismTier
        }
    }

    public enum ChannelTransform: String, Sendable, Codable, Equatable {
        case identity
        case affineTanh
        case affineSigmoid
        case categorical
    }

    public struct Channel: Sendable, Codable, Equatable {
        public let index: Int
        public let id: String
        public let unit: String
        public let lowerBound: Double?
        public let upperBound: Double?
        public let transform: ChannelTransform

        public init(
            index: Int,
            id: String,
            unit: String,
            lowerBound: Double? = nil,
            upperBound: Double? = nil,
            transform: ChannelTransform = .identity
        ) {
            self.index = index
            self.id = id
            self.unit = unit
            self.lowerBound = lowerBound
            self.upperBound = upperBound
            self.transform = transform
        }
    }

    public struct Space: Sendable, Codable, Equatable {
        public let id: String
        public let version: String
        public let digest: String
        public let channels: [Channel]

        public init(id: String, version: String, digest: String, channels: [Channel]) {
            self.id = id
            self.version = version
            self.digest = digest
            self.channels = channels
        }
    }

    public struct Spaces: Sendable, Codable, Equatable {
        public let observation: Space
        public let criticState: Space?
        public let policyAction: Space
        public let realizedControl: Space
        public let actuatorCommand: Space
        public let worldState: Space?

        public init(
            observation: Space,
            criticState: Space? = nil,
            policyAction: Space,
            realizedControl: Space,
            actuatorCommand: Space,
            worldState: Space? = nil
        ) {
            self.observation = observation
            self.criticState = criticState
            self.policyAction = policyAction
            self.realizedControl = realizedControl
            self.actuatorCommand = actuatorCommand
            self.worldState = worldState
        }
    }

    public struct Timing: Sendable, Codable, Equatable {
        public let physicsTimeStep: Double
        public let controlPeriodTicks: UInt64

        public init(physicsTimeStep: Double, controlPeriodTicks: UInt64) {
            self.physicsTimeStep = physicsTimeStep
            self.controlPeriodTicks = controlPeriodTicks
        }
    }

    public struct Semantics: Sendable, Codable, Equatable {
        public let rewardDescriptorDigest: String
        public let safetyCostDescriptorDigest: String
        public let failureDescriptorDigest: String
        public let taskQualityDescriptorDigest: String

        public init(
            rewardDescriptorDigest: String,
            safetyCostDescriptorDigest: String,
            failureDescriptorDigest: String,
            taskQualityDescriptorDigest: String
        ) {
            self.rewardDescriptorDigest = rewardDescriptorDigest
            self.safetyCostDescriptorDigest = safetyCostDescriptorDigest
            self.failureDescriptorDigest = failureDescriptorDigest
            self.taskQualityDescriptorDigest = taskQualityDescriptorDigest
        }
    }

    public struct Policy: Sendable, Codable, Equatable {
        public let policyID: String
        public let checkpointDigest: String
        public let distributionContractDigest: String

        public init(policyID: String, checkpointDigest: String, distributionContractDigest: String) {
            self.policyID = policyID
            self.checkpointDigest = checkpointDigest
            self.distributionContractDigest = distributionContractDigest
        }
    }

    public struct Provenance: Sendable, Codable, Equatable {
        public struct Migration: Sendable, Codable, Equatable {
            public enum Classification: String, Sendable, Codable, Equatable {
                case migrated
                case downgradedToOffPolicy
            }

            public let sourceSchemaVersion: Int
            public let classification: Classification
            public let unavailableFacts: [String]

            public init(
                sourceSchemaVersion: Int,
                classification: Classification,
                unavailableFacts: [String] = []
            ) {
                self.sourceSchemaVersion = sourceSchemaVersion
                self.classification = classification
                self.unavailableFacts = unavailableFacts
            }
        }

        public let codeDigest: String
        public let configurationDigest: String
        public let embodimentDigest: String
        public let sourceDatasetDigest: String?
        public let importerID: String?
        public let migration: Migration?

        public init(
            codeDigest: String,
            configurationDigest: String,
            embodimentDigest: String,
            sourceDatasetDigest: String? = nil,
            importerID: String? = nil,
            migration: Migration? = nil
        ) {
            self.codeDigest = codeDigest
            self.configurationDigest = configurationDigest
            self.embodimentDigest = embodimentDigest
            self.sourceDatasetDigest = sourceDatasetDigest
            self.importerID = importerID
            self.migration = migration
        }
    }

    public let identity: Identity
    public let producer: Producer
    public let recordKind: KuyuDatasetRecord.Kind
    public let execution: Execution
    public let spaces: Spaces
    public let timing: Timing
    public let semantics: Semantics
    public let policy: Policy?
    public let policyContext: KuyuPolicyContextContract?
    public let provenance: Provenance

    public init(
        identity: Identity,
        producer: Producer,
        recordKind: KuyuDatasetRecord.Kind,
        execution: Execution,
        spaces: Spaces,
        timing: Timing,
        semantics: Semantics,
        policy: Policy? = nil,
        policyContext: KuyuPolicyContextContract? = nil,
        provenance: Provenance
    ) {
        self.identity = identity
        self.producer = producer
        self.recordKind = recordKind
        self.execution = execution
        self.spaces = spaces
        self.timing = timing
        self.semantics = semantics
        self.policy = policy
        self.policyContext = policyContext
        self.provenance = provenance
    }
}
