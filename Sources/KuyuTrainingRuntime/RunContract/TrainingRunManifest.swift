import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

/// Immutable identity of a training run, written exactly once at creation as
/// `manifest.json` and never modified afterwards.
///
/// The manifest captures everything needed to interpret and reproduce a run:
/// what was trained, with which pipeline version, from which code state, with
/// which determinism stamp, on which host, and how it was launched.
public struct TrainingRunManifest: Sendable, Codable, Equatable {
    /// Source-code identity at launch time.
    public struct CodeIdentity: Sendable, Codable, Equatable {
        public let gitHead: String
        public let gitDirty: Bool
        public let buildConfiguration: String

        public init(gitHead: String, gitDirty: Bool, buildConfiguration: String) {
            self.gitHead = gitHead
            self.gitDirty = gitDirty
            self.buildConfiguration = buildConfiguration
        }
    }

    /// Seeds and determinism tier claimed by the run.
    ///
    /// `mlxGlobalSeed` is mandatory: a run that does not seed the global MLX
    /// RNG cannot claim Tier-0 and must record `tier >= 1`.
    public struct DeterminismStamp: Sendable, Codable, Equatable {
        public let mlxGlobalSeed: UInt64
        public let noiseSeedSalt: UInt64?
        public let tier: Int

        public init(mlxGlobalSeed: UInt64, noiseSeedSalt: UInt64?, tier: Int) {
            self.mlxGlobalSeed = mlxGlobalSeed
            self.noiseSeedSalt = noiseSeedSalt
            self.tier = tier
        }
    }

    /// Host and writer-process identity.
    public struct HostIdentity: Sendable, Codable, Equatable {
        public let hostName: String
        public let osVersion: String
        public let processIdentifier: Int32

        public init(hostName: String, osVersion: String, processIdentifier: Int32) {
            self.hostName = hostName
            self.osVersion = osVersion
            self.processIdentifier = processIdentifier
        }
    }

    /// How the run was launched.
    ///
    /// `environmentOverrides` records only the allow-listed `KUYU_*` /
    /// `MANAS_*` variables that influence training — never the full
    /// environment.
    public struct LaunchRecord: Sendable, Codable, Equatable {
        public let executablePath: String
        public let arguments: [String]
        public let environmentOverrides: [String: String]

        public init(executablePath: String, arguments: [String], environmentOverrides: [String: String]) {
            self.executablePath = executablePath
            self.arguments = arguments
            self.environmentOverrides = environmentOverrides
        }
    }

    public let schemaVersion: Int
    public let runID: TrainingRunID
    public let createdAt: Date
    public let task: String
    public let profile: String
    public let semanticVersion: String
    public let cacheKey: String?
    public let code: CodeIdentity
    public let determinism: DeterminismStamp
    public let host: HostIdentity
    public let launch: LaunchRecord

    public init(
        schemaVersion: Int = TrainingRunContractSchema.version,
        runID: TrainingRunID,
        createdAt: Date,
        task: String,
        profile: String,
        semanticVersion: String,
        cacheKey: String?,
        code: CodeIdentity,
        determinism: DeterminismStamp,
        host: HostIdentity,
        launch: LaunchRecord
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.createdAt = createdAt
        self.task = task
        self.profile = profile
        self.semanticVersion = semanticVersion
        self.cacheKey = cacheKey
        self.code = code
        self.determinism = determinism
        self.host = host
        self.launch = launch
    }

    /// Validates structural invariants before the manifest is persisted.
    public func validate() throws {
        guard schemaVersion == TrainingRunContractSchema.version else {
            throw TrainingRunContractError.unsupportedSchemaVersion(
                found: schemaVersion,
                supported: TrainingRunContractSchema.version
            )
        }
        guard !runID.rawValue.isEmpty else {
            throw TrainingRunContractError.invalidManifest(reason: "runID is empty")
        }
        guard !runID.rawValue.contains("/"), runID.rawValue != ".", runID.rawValue != ".." else {
            throw TrainingRunContractError.invalidManifest(
                reason: "runID is not a valid directory name: \(runID.rawValue)"
            )
        }
        guard !task.isEmpty else {
            throw TrainingRunContractError.invalidManifest(reason: "task is empty")
        }
        guard !profile.isEmpty else {
            throw TrainingRunContractError.invalidManifest(reason: "profile is empty")
        }
        guard !semanticVersion.isEmpty else {
            throw TrainingRunContractError.invalidManifest(reason: "semanticVersion is empty")
        }
        guard (0...2).contains(determinism.tier) else {
            throw TrainingRunContractError.invalidManifest(
                reason: "determinism tier must be in 0...2, found \(determinism.tier)"
            )
        }
    }
}
