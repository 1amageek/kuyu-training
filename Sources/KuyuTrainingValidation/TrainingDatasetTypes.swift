import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

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
    public let robotManifestHash: String
    public let suiteVersion: String
    public let plannerProfileID: String?
    public let curriculumPolicyID: String?

    public init(
        codeHash: String,
        configHash: String,
        robotManifestHash: String,
        suiteVersion: String,
        plannerProfileID: String? = nil,
        curriculumPolicyID: String? = nil
    ) {
        self.codeHash = codeHash
        self.configHash = configHash
        self.robotManifestHash = robotManifestHash
        self.suiteVersion = suiteVersion
        self.plannerProfileID = plannerProfileID
        self.curriculumPolicyID = curriculumPolicyID
    }
}

public struct TrainingAltitudeHoldReferenceMetadata: Sendable, Codable, Equatable {
    public let targetPosition: Axis3
    public let tolerance: Double
    public let referenceVerticalVelocity: Double

    public init(
        targetPosition: Axis3,
        tolerance: Double,
        referenceVerticalVelocity: Double
    ) {
        self.targetPosition = targetPosition
        self.tolerance = tolerance
        self.referenceVerticalVelocity = referenceVerticalVelocity
    }

    public init(reference: ReferenceQuadrotorAltitudeHoldReference) {
        self.init(
            targetPosition: reference.targetPosition,
            tolerance: reference.tolerance,
            referenceVerticalVelocity: reference.referenceVerticalVelocity
        )
    }
}

public struct TrainingTaskReferenceMetadata: Sendable, Codable, Equatable {
    public let altitudeHold: TrainingAltitudeHoldReferenceMetadata?

    public init(altitudeHold: TrainingAltitudeHoldReferenceMetadata? = nil) {
        self.altitudeHold = altitudeHold
    }
}

public struct TrainingDatasetMetadata: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 4

    public let schemaVersion: Int
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
    public let episodeId: String?
    public let policyId: String?
    public let rewardSum: Double?
    public let done: Bool?
    public let truncated: Bool?
    public let terminalReason: String?
    public let rewardDescriptor: RewardDescriptor?
    public let taskReference: TrainingTaskReferenceMetadata?
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
        schemaVersion: Int = TrainingDatasetMetadata.currentSchemaVersion,
        failureReason: String? = nil,
        failureTime: Double? = nil,
        episodeId: String? = nil,
        policyId: String? = nil,
        rewardSum: Double? = nil,
        done: Bool? = nil,
        truncated: Bool? = nil,
        terminalReason: String? = nil,
        rewardDescriptor: RewardDescriptor? = nil,
        taskReference: TrainingTaskReferenceMetadata? = nil,
        observation: TrainingObservationMetadata? = nil,
        provenance: TrainingProvenanceManifest? = nil
    ) {
        self.schemaVersion = schemaVersion
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
        self.episodeId = episodeId
        self.policyId = policyId
        self.rewardSum = rewardSum
        self.done = done
        self.truncated = truncated
        self.terminalReason = terminalReason
        self.rewardDescriptor = rewardDescriptor
        self.taskReference = taskReference
        self.observation = observation
        self.provenance = provenance
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case scenarioId
        case seed
        case timeStep
        case determinismTier
        case configHash
        case channelCount
        case driveCount
        case recordCount
        case failureReason
        case failureTime
        case episodeId
        case policyId
        case rewardSum
        case done
        case truncated
        case terminalReason
        case rewardDescriptor
        case taskReference
        case observation
        case provenance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        scenarioId = try container.decode(String.self, forKey: .scenarioId)
        seed = try container.decode(UInt64.self, forKey: .seed)
        timeStep = try container.decode(Double.self, forKey: .timeStep)
        determinismTier = try container.decode(String.self, forKey: .determinismTier)
        configHash = try container.decode(String.self, forKey: .configHash)
        channelCount = try container.decode(Int.self, forKey: .channelCount)
        driveCount = try container.decode(Int.self, forKey: .driveCount)
        recordCount = try container.decode(Int.self, forKey: .recordCount)
        failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
        failureTime = try container.decodeIfPresent(Double.self, forKey: .failureTime)
        episodeId = try container.decodeIfPresent(String.self, forKey: .episodeId)
        policyId = try container.decodeIfPresent(String.self, forKey: .policyId)
        rewardSum = try container.decodeIfPresent(Double.self, forKey: .rewardSum)
        done = try container.decodeIfPresent(Bool.self, forKey: .done)
        truncated = try container.decodeIfPresent(Bool.self, forKey: .truncated)
        terminalReason = try container.decodeIfPresent(String.self, forKey: .terminalReason)
        rewardDescriptor = try container.decodeIfPresent(RewardDescriptor.self, forKey: .rewardDescriptor)
        taskReference = try container.decodeIfPresent(TrainingTaskReferenceMetadata.self, forKey: .taskReference)
        observation = try container.decodeIfPresent(TrainingObservationMetadata.self, forKey: .observation)
        provenance = try container.decodeIfPresent(TrainingProvenanceManifest.self, forKey: .provenance)
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
    public let physicsState: [Double]?
    public let actualState: [Double]?
    public let actionValues: [Double]?
    public let continueValue: Double?
    public let reward: Double?
    /// Per-step safety cost for constrained RL. Nil means no cost signal was
    /// recorded; constrained pipelines must fail closed instead of assuming zero.
    public let cost: Double?
    public let done: Bool?
    public let truncated: Bool?
    public let episodeId: String?
    public let policyId: String?

    public init(
        time: Double,
        sensors: [TrainingSensorSample],
        driveIntents: [TrainingDriveIntent],
        reflexCorrections: [TrainingReflexCorrection],
        physicsState: [Double]? = nil,
        actualState: [Double]? = nil,
        actionValues: [Double]? = nil,
        continueValue: Double? = nil,
        reward: Double? = nil,
        cost: Double? = nil,
        done: Bool? = nil,
        truncated: Bool? = nil,
        episodeId: String? = nil,
        policyId: String? = nil
    ) {
        self.time = time
        self.sensors = sensors
        self.driveIntents = driveIntents
        self.reflexCorrections = reflexCorrections
        self.physicsState = physicsState
        self.actualState = actualState
        self.actionValues = actionValues
        self.continueValue = continueValue
        self.reward = reward
        self.cost = cost
        self.done = done
        self.truncated = truncated
        self.episodeId = episodeId
        self.policyId = policyId
    }
}

public struct TrainingDataset: Sendable, Equatable {
    public static let supportedSchemaVersions: Set<Int> = [3, TrainingDatasetMetadata.currentSchemaVersion]

    public enum LoadError: Error, Equatable {
        case unsupportedSchemaVersion(found: Int, supported: [Int])
    }

    public let metadata: TrainingDatasetMetadata
    public let records: [TrainingDatasetRecord]

    public init(metadata: TrainingDatasetMetadata, records: [TrainingDatasetRecord]) {
        self.metadata = metadata
        self.records = records
    }

    public static func load(from directory: URL) throws -> TrainingDataset {
        let decoder = JSONDecoder()
        let metadataURL = directory.appendingPathComponent("meta.json")
        let recordsURL = directory.appendingPathComponent("records.jsonl")
        let metadata = try decoder.decode(
            TrainingDatasetMetadata.self,
            from: Data(contentsOf: metadataURL)
        )
        guard supportedSchemaVersions.contains(metadata.schemaVersion) else {
            throw LoadError.unsupportedSchemaVersion(
                found: metadata.schemaVersion,
                supported: Array(supportedSchemaVersions).sorted()
            )
        }
        let lines = try String(contentsOf: recordsURL, encoding: .utf8)
            .split(separator: "\n")
            .filter { !$0.isEmpty }
        let records = try lines.map { line in
            try decoder.decode(TrainingDatasetRecord.self, from: Data(line.utf8))
        }
        return TrainingDataset(metadata: metadata, records: records)
    }
}
