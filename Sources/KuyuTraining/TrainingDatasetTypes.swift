import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios

public struct TrainingObservationClockMetadata: Sendable, Codable, Equatable {
    public let timebase: String
    public let epoch: String?
    public let maxSkewMs: Double
    public let syncPolicy: String

    public init(
        timebase: String,
        epoch: String? = nil,
        maxSkewMs: Double,
        syncPolicy: String
    ) {
        self.timebase = timebase
        self.epoch = epoch
        self.maxSkewMs = maxSkewMs
        self.syncPolicy = syncPolicy
    }
}

public struct TrainingObservationProvenanceMetadata: Sendable, Codable, Equatable {
    public let producer: String?
    public let transport: String?
    public let notes: String?

    public init(
        producer: String? = nil,
        transport: String? = nil,
        notes: String? = nil
    ) {
        self.producer = producer
        self.transport = transport
        self.notes = notes
    }
}

public struct TrainingObservationModalityMetadata: Sendable, Codable, Equatable {
    public let id: String
    public let type: String
    public let channels: [String]?
    public let timestampSource: String
    public let provenance: TrainingObservationProvenanceMetadata?

    public init(
        id: String,
        type: String,
        channels: [String]? = nil,
        timestampSource: String,
        provenance: TrainingObservationProvenanceMetadata? = nil
    ) {
        self.id = id
        self.type = type
        self.channels = channels
        self.timestampSource = timestampSource
        self.provenance = provenance
    }
}

public struct TrainingObservationMetadata: Sendable, Codable, Equatable {
    public let clock: TrainingObservationClockMetadata?
    public let modalities: [TrainingObservationModalityMetadata]?

    public init(
        clock: TrainingObservationClockMetadata? = nil,
        modalities: [TrainingObservationModalityMetadata]? = nil
    ) {
        self.clock = clock
        self.modalities = modalities
    }
}

public struct TrainingProvenanceManifest: Sendable, Codable, Equatable {
    public let codeHash: String
    public let configHash: String
    public let descriptorHash: String
    public let suiteVersion: String
    public let plannerProfileID: String?
    public let curriculumPolicyID: String?

    public init(
        codeHash: String,
        configHash: String,
        descriptorHash: String,
        suiteVersion: String,
        plannerProfileID: String? = nil,
        curriculumPolicyID: String? = nil
    ) {
        self.codeHash = codeHash
        self.configHash = configHash
        self.descriptorHash = descriptorHash
        self.suiteVersion = suiteVersion
        self.plannerProfileID = plannerProfileID
        self.curriculumPolicyID = curriculumPolicyID
    }
}

public struct TrainingDatasetMetadata: Sendable, Codable, Equatable {
    public let scenarioId: String
    public let seed: UInt64
    public let timeStep: Double
    public let determinismTier: String
    public let configHash: String
    public let channelCount: Int
    public let driveCount: Int
    public let recordCount: Int
    public let failureReason: String?
    public let failureTime: Double?
    public let observation: TrainingObservationMetadata?
    public let provenance: TrainingProvenanceManifest?

    public init(
        scenarioId: String,
        seed: UInt64,
        timeStep: Double,
        determinismTier: String,
        configHash: String,
        channelCount: Int,
        driveCount: Int,
        recordCount: Int,
        failureReason: String? = nil,
        failureTime: Double? = nil,
        observation: TrainingObservationMetadata? = nil,
        provenance: TrainingProvenanceManifest? = nil
    ) {
        self.scenarioId = scenarioId
        self.seed = seed
        self.timeStep = timeStep
        self.determinismTier = determinismTier
        self.configHash = configHash
        self.channelCount = channelCount
        self.driveCount = driveCount
        self.recordCount = recordCount
        self.failureReason = failureReason
        self.failureTime = failureTime
        self.observation = observation
        self.provenance = provenance
    }
}

public struct TrainingSensorSample: Sendable, Codable, Equatable {
    public let channelIndex: UInt32
    public let value: Double
    public let timestamp: Double

    public init(channelIndex: UInt32, value: Double, timestamp: Double) {
        self.channelIndex = channelIndex
        self.value = value
        self.timestamp = timestamp
    }
}

public struct TrainingDriveIntent: Sendable, Codable, Equatable {
    public let driveIndex: UInt32
    public let value: Double
    public let parameters: [Double]

    public init(driveIndex: UInt32, value: Double, parameters: [Double] = []) {
        self.driveIndex = driveIndex
        self.value = value
        self.parameters = parameters
    }
}

public struct TrainingReflexCorrection: Sendable, Codable, Equatable {
    public let driveIndex: UInt32
    public let clamp: Double
    public let damping: Double
    public let delta: Double

    public init(driveIndex: UInt32, clamp: Double, damping: Double, delta: Double) {
        self.driveIndex = driveIndex
        self.clamp = clamp
        self.damping = damping
        self.delta = delta
    }
}

public struct TrainingDatasetRecord: Sendable, Codable, Equatable {
    public let time: Double
    public let sensors: [TrainingSensorSample]
    public let driveIntents: [TrainingDriveIntent]
    public let reflexCorrections: [TrainingReflexCorrection]

    public init(
        time: Double,
        sensors: [TrainingSensorSample],
        driveIntents: [TrainingDriveIntent],
        reflexCorrections: [TrainingReflexCorrection]
    ) {
        self.time = time
        self.sensors = sensors
        self.driveIntents = driveIntents
        self.reflexCorrections = reflexCorrections
    }
}
