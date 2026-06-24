import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public struct CheckpointEvaluationScenarioKey: Sendable, Codable, Hashable, Comparable {
    public let scenarioID: String
    public let seed: UInt64

    public init(scenarioID: String, seed: UInt64) {
        self.scenarioID = scenarioID
        self.seed = seed
    }

    public init(qualitySummary: ReferenceQuadrotorTaskQualitySummary) {
        self.init(scenarioID: qualitySummary.scenarioID, seed: qualitySummary.seed)
    }

    public static func < (
        lhs: CheckpointEvaluationScenarioKey,
        rhs: CheckpointEvaluationScenarioKey
    ) -> Bool {
        if lhs.scenarioID != rhs.scenarioID {
            return lhs.scenarioID < rhs.scenarioID
        }
        return lhs.seed < rhs.seed
    }
}

public struct CheckpointEvaluationScenarioHorizon: Sendable, Codable, Hashable, Comparable {
    public let scenarioID: String
    public let seed: UInt64
    public let durationSeconds: Double
    public let timeStepSeconds: Double
    public let stepCount: Int

    public init(
        scenarioID: String,
        seed: UInt64,
        durationSeconds: Double,
        timeStepSeconds: Double,
        stepCount: Int
    ) {
        self.scenarioID = scenarioID
        self.seed = seed
        self.durationSeconds = durationSeconds
        self.timeStepSeconds = timeStepSeconds
        self.stepCount = stepCount
    }

    public init(definition: ReferenceQuadrotorScenarioDefinition) {
        let duration = definition.config.duration
        let timeStep = definition.config.timeStep.delta
        self.init(
            scenarioID: definition.config.id.rawValue,
            seed: definition.config.seed.rawValue,
            durationSeconds: duration,
            timeStepSeconds: timeStep,
            stepCount: Int((duration / timeStep).rounded(.down))
        )
    }

    public var key: CheckpointEvaluationScenarioKey {
        CheckpointEvaluationScenarioKey(scenarioID: scenarioID, seed: seed)
    }

    public static func < (
        lhs: CheckpointEvaluationScenarioHorizon,
        rhs: CheckpointEvaluationScenarioHorizon
    ) -> Bool {
        if lhs.key != rhs.key {
            return lhs.key < rhs.key
        }
        if lhs.durationSeconds != rhs.durationSeconds {
            return lhs.durationSeconds < rhs.durationSeconds
        }
        if lhs.timeStepSeconds != rhs.timeStepSeconds {
            return lhs.timeStepSeconds < rhs.timeStepSeconds
        }
        return lhs.stepCount < rhs.stepCount
    }
}

public struct CheckpointEvaluationRequest: Sendable, Equatable {
    public let evaluationID: String
    public let profile: TaskEvaluationProfile
    public let checkpointURL: URL
    public let artifactRoot: URL

    public init(
        evaluationID: String = "checkpoint-eval-\(UUID().uuidString)",
        profile: TaskEvaluationProfile,
        checkpointURL: URL,
        artifactRoot: URL
    ) {
        self.evaluationID = evaluationID
        self.profile = profile
        self.checkpointURL = checkpointURL
        self.artifactRoot = artifactRoot
    }
}

public protocol CheckpointEvaluating: Sendable {
    func evaluateCheckpoint(request: CheckpointEvaluationRequest) async throws -> CheckpointEvaluationArtifact
}

public struct CheckpointEvaluationArtifact: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 2
    public static let fileName = "checkpoint-evaluation.json"

    public let schemaVersion: Int
    public let evaluationID: String
    public let startedAt: Date
    public let task: String
    public let profileID: String
    public let checkpointPath: String
    public let teacherScore: Double
    public let policyScore: Double
    public let scoreDeltaFromTeacher: Double
    public let teacherPassed: Bool
    public let policyPassed: Bool
    public let failureReasons: [String]
    public let expectedQualityKeys: [CheckpointEvaluationScenarioKey]
    public let qualitySummary: [ReferenceQuadrotorTaskQualitySummary]
    public let scenarioHorizons: [CheckpointEvaluationScenarioHorizon]?
    public let motorMAE: Double?
    public let driveMAE: Double?
    public let finalAltitudeDelta: Double?
    public let policyAverageMotorFinalOutputByIndex: [Double]?
    public let teacherAverageMotorFinalOutputByIndex: [Double]?
    public let diagnostics: CheckpointEvaluationDiagnostics?

    public init(
        schemaVersion: Int = CheckpointEvaluationArtifact.currentSchemaVersion,
        evaluationID: String,
        startedAt: Date,
        task: String,
        profileID: String,
        checkpointPath: String,
        teacherScore: Double,
        policyScore: Double,
        teacherPassed: Bool,
        policyPassed: Bool,
        failureReasons: [String],
        expectedQualityKeys: [CheckpointEvaluationScenarioKey],
        qualitySummary: [ReferenceQuadrotorTaskQualitySummary],
        scenarioHorizons: [CheckpointEvaluationScenarioHorizon]? = nil,
        motorMAE: Double?,
        driveMAE: Double?,
        finalAltitudeDelta: Double?,
        policyAverageMotorFinalOutputByIndex: [Double]?,
        teacherAverageMotorFinalOutputByIndex: [Double]?,
        diagnostics: CheckpointEvaluationDiagnostics?
    ) {
        self.schemaVersion = schemaVersion
        self.evaluationID = evaluationID
        self.startedAt = startedAt
        self.task = task
        self.profileID = profileID
        self.checkpointPath = checkpointPath
        self.teacherScore = teacherScore
        self.policyScore = policyScore
        self.scoreDeltaFromTeacher = policyScore - teacherScore
        self.teacherPassed = teacherPassed
        self.policyPassed = policyPassed
        self.failureReasons = failureReasons
        self.expectedQualityKeys = expectedQualityKeys
        self.qualitySummary = qualitySummary
        self.scenarioHorizons = scenarioHorizons
        self.motorMAE = motorMAE
        self.driveMAE = driveMAE
        self.finalAltitudeDelta = finalAltitudeDelta
        self.policyAverageMotorFinalOutputByIndex = policyAverageMotorFinalOutputByIndex
        self.teacherAverageMotorFinalOutputByIndex = teacherAverageMotorFinalOutputByIndex
        self.diagnostics = diagnostics
    }

}

public enum CheckpointEvaluationArtifactValidator {
    public enum ValidationError: Error, Sendable, Equatable {
        case schemaVersionMismatch(expected: Int, actual: Int)
        case taskMismatch(expected: String, actual: String)
        case profileMismatch(expected: String, actual: String)
        case checkpointMismatch(expected: String, actual: String)
        case nonFiniteMetric(String)
        case failedPolicy([String])
        case missingTaskQuality(String)
        case missingExpectedTaskQuality(scenarioID: String, seed: UInt64)
        case unexpectedTaskQuality(scenarioID: String, seed: UInt64)
        case duplicateExpectedTaskQuality(scenarioID: String, seed: UInt64)
        case duplicateTaskQuality(scenarioID: String, seed: UInt64)
        case duplicateScenarioHorizon(scenarioID: String, seed: UInt64)
        case missingScenarioHorizon(scenarioID: String, seed: UInt64)
        case unexpectedScenarioHorizon(scenarioID: String, seed: UInt64)
        case invalidScenarioHorizon(scenarioID: String, seed: UInt64)
        case qualityTaskMismatch(expected: String, actual: String)
        case qualityEvaluatorMismatch(expected: String, actual: String)
        case failedTaskQuality(scenarioID: String, reasons: [String])
    }

    public static func validate(
        _ artifact: CheckpointEvaluationArtifact,
        expectedProfile: TaskEvaluationProfile,
        expectedCheckpointPath: String,
        requiresPolicyPass: Bool
    ) throws {
        guard artifact.schemaVersion == CheckpointEvaluationArtifact.currentSchemaVersion else {
            throw ValidationError.schemaVersionMismatch(
                expected: CheckpointEvaluationArtifact.currentSchemaVersion,
                actual: artifact.schemaVersion
            )
        }
        guard artifact.task == expectedProfile.task else {
            throw ValidationError.taskMismatch(expected: expectedProfile.task, actual: artifact.task)
        }
        guard artifact.profileID == expectedProfile.profileID else {
            throw ValidationError.profileMismatch(expected: expectedProfile.profileID, actual: artifact.profileID)
        }
        guard artifact.checkpointPath == expectedCheckpointPath else {
            throw ValidationError.checkpointMismatch(expected: expectedCheckpointPath, actual: artifact.checkpointPath)
        }
        try validateFinite(artifact.teacherScore, name: "teacherScore")
        try validateFinite(artifact.policyScore, name: "policyScore")
        try validateFinite(artifact.scoreDeltaFromTeacher, name: "scoreDeltaFromTeacher")
        try validateFinite(artifact.motorMAE, name: "motorMAE")
        try validateFinite(artifact.driveMAE, name: "driveMAE")
        try validateFinite(artifact.finalAltitudeDelta, name: "finalAltitudeDelta")
        try validateFinite(artifact.policyAverageMotorFinalOutputByIndex, name: "policyAverageMotorFinalOutputByIndex")
        try validateFinite(artifact.teacherAverageMotorFinalOutputByIndex, name: "teacherAverageMotorFinalOutputByIndex")
        try validateDiagnostics(artifact.diagnostics)
        try validateQualitySummary(
            expectedKeys: artifact.expectedQualityKeys,
            artifact.qualitySummary,
            expectedProfile: expectedProfile,
            requiresPolicyPass: requiresPolicyPass
        )
        try validateScenarioHorizons(
            artifact.scenarioHorizons,
            expectedKeys: artifact.expectedQualityKeys
        )
        if requiresPolicyPass && !artifact.policyPassed {
            throw ValidationError.failedPolicy(artifact.failureReasons)
        }
    }

    private static func validateQualitySummary(
        expectedKeys: [CheckpointEvaluationScenarioKey],
        _ summaries: [ReferenceQuadrotorTaskQualitySummary],
        expectedProfile: TaskEvaluationProfile,
        requiresPolicyPass: Bool
    ) throws {
        if expectedProfile.requiresParentCheckpointEvaluation && expectedKeys.isEmpty {
            throw ValidationError.missingTaskQuality(expectedProfile.task)
        }
        var expectedSet = Set<CheckpointEvaluationScenarioKey>()
        for key in expectedKeys {
            guard expectedSet.insert(key).inserted else {
                throw ValidationError.duplicateExpectedTaskQuality(
                    scenarioID: key.scenarioID,
                    seed: key.seed
                )
            }
        }
        var actualSet = Set<CheckpointEvaluationScenarioKey>()
        for summary in summaries {
            let key = CheckpointEvaluationScenarioKey(qualitySummary: summary)
            guard actualSet.insert(key).inserted else {
                throw ValidationError.duplicateTaskQuality(
                    scenarioID: key.scenarioID,
                    seed: key.seed
                )
            }
            guard summary.task == expectedProfile.task else {
                throw ValidationError.qualityTaskMismatch(expected: expectedProfile.task, actual: summary.task)
            }
            guard summary.evaluatorID == expectedProfile.qualityEvaluatorID else {
                throw ValidationError.qualityEvaluatorMismatch(
                    expected: expectedProfile.qualityEvaluatorID,
                    actual: summary.evaluatorID
                )
            }
            try validateFinite(summary.targetZ, name: "qualitySummary.targetZ")
            try validateFinite(summary.tolerance, name: "qualitySummary.tolerance")
            try validateFinite(summary.warmupTime, name: "qualitySummary.warmupTime")
            try validateFinite(summary.requiredHoldTime, name: "qualitySummary.requiredHoldTime")
            try validateFinite(summary.achievedHoldTime, name: "qualitySummary.achievedHoldTime")
            try validateFinite(
                summary.maxAltitudeErrorAfterWarmup,
                name: "qualitySummary.maxAltitudeErrorAfterWarmup"
            )
            try validateFinite(
                summary.maxVerticalVelocityAfterWarmup,
                name: "qualitySummary.maxVerticalVelocityAfterWarmup"
            )
            if requiresPolicyPass && !summary.passed {
                throw ValidationError.failedTaskQuality(
                    scenarioID: summary.scenarioID,
                    reasons: summary.failureReasons
                )
            }
        }
        if expectedSet != actualSet {
            let missing = expectedSet.subtracting(actualSet).sorted()
            if let first = missing.first {
                throw ValidationError.missingExpectedTaskQuality(
                    scenarioID: first.scenarioID,
                    seed: first.seed
                )
            }
            let unexpected = actualSet.subtracting(expectedSet).sorted()
            if let first = unexpected.first {
                throw ValidationError.unexpectedTaskQuality(
                    scenarioID: first.scenarioID,
                    seed: first.seed
                )
            }
        }
    }

    private static func validateFinite(_ value: Double?, name: String) throws {
        guard let value else { return }
        guard value.isFinite else {
            throw ValidationError.nonFiniteMetric(name)
        }
    }

    private static func validateFinite(_ values: [Double]?, name: String) throws {
        guard let values else { return }
        guard values.allSatisfy(\.isFinite) else {
            throw ValidationError.nonFiniteMetric(name)
        }
    }

    private static func validateScenarioHorizons(
        _ horizons: [CheckpointEvaluationScenarioHorizon]?,
        expectedKeys: [CheckpointEvaluationScenarioKey]
    ) throws {
        guard let horizons else {
            return
        }
        var horizonSet = Set<CheckpointEvaluationScenarioKey>()
        for horizon in horizons {
            guard horizonSet.insert(horizon.key).inserted else {
                throw ValidationError.duplicateScenarioHorizon(
                    scenarioID: horizon.scenarioID,
                    seed: horizon.seed
                )
            }
            guard horizon.durationSeconds.isFinite,
                  horizon.timeStepSeconds.isFinite,
                  horizon.durationSeconds > 0,
                  horizon.timeStepSeconds > 0,
                  horizon.stepCount > 0,
                  horizon.stepCount == Int((horizon.durationSeconds / horizon.timeStepSeconds).rounded(.down)) else {
                throw ValidationError.invalidScenarioHorizon(
                    scenarioID: horizon.scenarioID,
                    seed: horizon.seed
                )
            }
        }
        let expectedSet = Set(expectedKeys)
        if horizonSet != expectedSet {
            let missing = expectedSet.subtracting(horizonSet).sorted()
            if let first = missing.first {
                throw ValidationError.missingScenarioHorizon(
                    scenarioID: first.scenarioID,
                    seed: first.seed
                )
            }
            let unexpected = horizonSet.subtracting(expectedSet).sorted()
            if let first = unexpected.first {
                throw ValidationError.unexpectedScenarioHorizon(
                    scenarioID: first.scenarioID,
                    seed: first.seed
                )
            }
        }
    }

    private static func validateDiagnostics(_ diagnostics: CheckpointEvaluationDiagnostics?) throws {
        guard let diagnostics else { return }
        try validateFinite(diagnostics.worstFinalAltitudeDelta, name: "diagnostics.worstFinalAltitudeDelta")
        try validateFinite(
            diagnostics.worstFinalVerticalVelocityDelta,
            name: "diagnostics.worstFinalVerticalVelocityDelta"
        )
        try validateFinite(diagnostics.worstMotorOutputMAE, name: "diagnostics.worstMotorOutputMAE")
        try validateFinite(
            diagnostics.earliestAltitudeDivergenceTime,
            name: "diagnostics.earliestAltitudeDivergenceTime"
        )
        for comparison in diagnostics.scenarioComparisons {
            try validateFinite(comparison.teacherFailureTime, name: "diagnostics.teacherFailureTime")
            try validateFinite(comparison.policyFailureTime, name: "diagnostics.policyFailureTime")
            try validateFinite(comparison.initialAltitudeDelta, name: "diagnostics.initialAltitudeDelta")
            try validateFinite(comparison.finalAltitudeDelta, name: "diagnostics.finalAltitudeDelta")
            try validateFinite(comparison.minAltitudeDelta, name: "diagnostics.minAltitudeDelta")
            try validateFinite(comparison.maxAltitudeDelta, name: "diagnostics.maxAltitudeDelta")
            try validateFinite(
                comparison.finalVerticalVelocityDelta,
                name: "diagnostics.finalVerticalVelocityDelta"
            )
            try validateFinite(comparison.altitudeDivergenceTime, name: "diagnostics.altitudeDivergenceTime")
            try validateFinite(comparison.driveActivationMAE, name: "diagnostics.driveActivationMAE")
            try validateFinite(comparison.motorOutputMAE, name: "diagnostics.motorOutputMAE")
            try validateFinite(
                comparison.policyInitialDriveActivation,
                name: "diagnostics.policyInitialDriveActivation"
            )
            try validateFinite(
                comparison.teacherInitialDriveActivation,
                name: "diagnostics.teacherInitialDriveActivation"
            )
            try validateFinite(comparison.policyInitialMotorOutput, name: "diagnostics.policyInitialMotorOutput")
            try validateFinite(comparison.teacherInitialMotorOutput, name: "diagnostics.teacherInitialMotorOutput")
            try validateFinite(
                comparison.policyEarlyDriveActivationAverage,
                name: "diagnostics.policyEarlyDriveActivationAverage"
            )
            try validateFinite(
                comparison.teacherEarlyDriveActivationAverage,
                name: "diagnostics.teacherEarlyDriveActivationAverage"
            )
            try validateFinite(
                comparison.policyEarlyMotorOutputAverage,
                name: "diagnostics.policyEarlyMotorOutputAverage"
            )
            try validateFinite(
                comparison.teacherEarlyMotorOutputAverage,
                name: "diagnostics.teacherEarlyMotorOutputAverage"
            )
            try validateFinite(comparison.policyAverageMotorOutput, name: "diagnostics.policyAverageMotorOutput")
            try validateFinite(comparison.teacherAverageMotorOutput, name: "diagnostics.teacherAverageMotorOutput")
            try validateFinite(
                comparison.policyAverageDriveActivation,
                name: "diagnostics.policyAverageDriveActivation"
            )
            try validateFinite(
                comparison.teacherAverageDriveActivation,
                name: "diagnostics.teacherAverageDriveActivation"
            )
        }
    }
}
