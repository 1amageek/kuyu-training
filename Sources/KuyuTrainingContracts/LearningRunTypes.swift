import Foundation

public enum LearningRunMode: String, Sendable, Codable, Equatable {
    case supervised
    case rlRollout
    case imaginationRL
}

public enum LearningRunTerminalState: String, Sendable, Codable, Equatable {
    case running
    case completed
    case failed
    case cancelled
    case rejected
}

public struct LearningRunManifest: Sendable, Codable, Equatable {
    public let runID: String
    public let mode: LearningRunMode
    public let robotManifestID: String?
    public let robotManifestHash: String?
    public let configHash: String
    public let suiteID: String
    public let seedSet: [UInt64]
    public let policyID: String
    public let parentCheckpointID: String?
    public let outputCheckpointID: String?
    public let workerCount: Int
    public let startedAt: Date
    public let completedAt: Date?
    public let terminalState: LearningRunTerminalState
    public let failureReason: String?

    public init(
        runID: String,
        mode: LearningRunMode,
        robotManifestID: String? = nil,
        robotManifestHash: String? = nil,
        configHash: String,
        suiteID: String,
        seedSet: [UInt64],
        policyID: String,
        parentCheckpointID: String? = nil,
        outputCheckpointID: String? = nil,
        workerCount: Int,
        startedAt: Date,
        completedAt: Date? = nil,
        terminalState: LearningRunTerminalState,
        failureReason: String? = nil
    ) {
        self.runID = runID
        self.mode = mode
        self.robotManifestID = robotManifestID
        self.robotManifestHash = robotManifestHash
        self.configHash = configHash
        self.suiteID = suiteID
        self.seedSet = seedSet
        self.policyID = policyID
        self.parentCheckpointID = parentCheckpointID
        self.outputCheckpointID = outputCheckpointID
        self.workerCount = workerCount
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.terminalState = terminalState
        self.failureReason = failureReason
    }

    public func completed(
        at completedAt: Date,
        terminalState: LearningRunTerminalState,
        outputCheckpointID: String?,
        failureReason: String? = nil
    ) -> LearningRunManifest {
        LearningRunManifest(
            runID: runID,
            mode: mode,
            robotManifestID: robotManifestID,
            robotManifestHash: robotManifestHash,
            configHash: configHash,
            suiteID: suiteID,
            seedSet: seedSet,
            policyID: policyID,
            parentCheckpointID: parentCheckpointID,
            outputCheckpointID: outputCheckpointID,
            workerCount: workerCount,
            startedAt: startedAt,
            completedAt: completedAt,
            terminalState: terminalState,
            failureReason: failureReason
        )
    }
}

public enum TrainingMetricKind: String, Sendable, Codable, Equatable, CaseIterable {
    case loss
    case validationLoss
    case score
    case rewardAverage
    case passRate
    case failureRate
    case safetyViolation
    case evaluationScenarioCount
    case workerThroughput
    case scoreDelta
    case safetyViolationDelta
    case safetyEvidenceAvailable
    case safetyRegression
    case policySatisfied
    case teacherDriveAverageMAE
    case teacherMotorAverageMAE
    case teacherFinalAltitudeDelta
    case teacherDivergenceRegression
}

public struct TrainingMetricRecord: Sendable, Codable, Equatable {
    public let runID: String
    public let iteration: Int
    public let kind: TrainingMetricKind
    public let value: Double
    public let step: Int?
    public let workerIndex: Int?
    public let snapshotID: String?
    public let rolloutShardURL: URL?
    public let timestamp: Date

    public init(
        runID: String,
        iteration: Int,
        kind: TrainingMetricKind,
        value: Double,
        step: Int? = nil,
        workerIndex: Int? = nil,
        snapshotID: String? = nil,
        rolloutShardURL: URL? = nil,
        timestamp: Date = Date()
    ) {
        self.runID = runID
        self.iteration = iteration
        self.kind = kind
        self.value = value
        self.step = step
        self.workerIndex = workerIndex
        self.snapshotID = snapshotID
        self.rolloutShardURL = rolloutShardURL
        self.timestamp = timestamp
    }
}

public struct ConvergenceSummary: Sendable, Codable, Equatable {
    public let runID: String
    public let accepted: Bool
    public let reason: String
    public let bestCheckpointID: String?
    public let finalTrainingLoss: Double?
    public let finalValidationLoss: Double?
    public let rewardMovingAverage: Double?
    public let passRate: Double
    public let failureRate: Double
    public let safetyRegressionDetected: Bool
    public let plateauDetected: Bool
    public let overfitRiskDetected: Bool

    public init(
        runID: String,
        accepted: Bool,
        reason: String,
        bestCheckpointID: String? = nil,
        finalTrainingLoss: Double? = nil,
        finalValidationLoss: Double? = nil,
        rewardMovingAverage: Double? = nil,
        passRate: Double,
        failureRate: Double,
        safetyRegressionDetected: Bool,
        plateauDetected: Bool,
        overfitRiskDetected: Bool
    ) {
        self.runID = runID
        self.accepted = accepted
        self.reason = reason
        self.bestCheckpointID = bestCheckpointID
        self.finalTrainingLoss = finalTrainingLoss
        self.finalValidationLoss = finalValidationLoss
        self.rewardMovingAverage = rewardMovingAverage
        self.passRate = passRate
        self.failureRate = failureRate
        self.safetyRegressionDetected = safetyRegressionDetected
        self.plateauDetected = plateauDetected
        self.overfitRiskDetected = overfitRiskDetected
    }
}
