import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public enum TrainingProbeStage: String, Sendable, Codable, Equatable {
    case teacherActiveAltitudeHold
    case initialPolicy
    case trainingIteration
    case trainedPolicy
}

public struct TrainingProbeConfig: Sendable, Equatable {
    public let probeID: String
    public let minScoreDelta: Double
    public let requireAcceptedCheckpoint: Bool
    public let requireTeacherPass: Bool
    public let requireTrainedPass: Bool

    public init(
        probeID: String = UUID().uuidString,
        minScoreDelta: Double = 0,
        requireAcceptedCheckpoint: Bool = true,
        requireTeacherPass: Bool = true,
        requireTrainedPass: Bool = true
    ) {
        self.probeID = probeID
        self.minScoreDelta = minScoreDelta
        self.requireAcceptedCheckpoint = requireAcceptedCheckpoint
        self.requireTeacherPass = requireTeacherPass
        self.requireTrainedPass = requireTrainedPass
    }
}

public struct TrainingProbeManifest: Sendable, Codable, Equatable {
    public let probeID: String
    public let trainingRunID: String
    public let startedAt: Date
    public let completedAt: Date?
    public let terminalState: LearningRunTerminalState
    public let failureReason: String?

    public init(
        probeID: String,
        trainingRunID: String,
        startedAt: Date,
        completedAt: Date? = nil,
        terminalState: LearningRunTerminalState,
        failureReason: String? = nil
    ) {
        self.probeID = probeID
        self.trainingRunID = trainingRunID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.terminalState = terminalState
        self.failureReason = failureReason
    }

    public func completed(
        at completedAt: Date,
        terminalState: LearningRunTerminalState,
        failureReason: String?
    ) -> TrainingProbeManifest {
        TrainingProbeManifest(
            probeID: probeID,
            trainingRunID: trainingRunID,
            startedAt: startedAt,
            completedAt: completedAt,
            terminalState: terminalState,
            failureReason: failureReason
        )
    }
}

public struct TrainingProbeRunSummary: Sendable, Codable, Equatable {
    public let stage: TrainingProbeStage
    public let score: Double
    public let suitePassed: Bool
    public let scenarioCount: Int
    public let safetyViolationSeconds: Double
    public let worstOvershootDegrees: Double?
    public let averageRecoveryTime: Double?
    public let averageHfStabilityScore: Double?
    public let diagnostics: TrainingProbeRunDiagnostics

    public init(stage: TrainingProbeStage, output: TrainingScenarioRunOutput) {
        self.stage = stage
        self.score = TrainingRunOrchestrator.score(from: output.summary)
        self.suitePassed = output.summary.suitePassed
        self.scenarioCount = output.summary.evaluations.count
        self.safetyViolationSeconds = output.summary.evaluations.reduce(0.0) { partial, evaluation in
            partial + evaluation.sustainedViolationSeconds
        }
        self.worstOvershootDegrees = output.summary.aggregate.worstOvershootDegrees
        self.averageRecoveryTime = output.summary.aggregate.averageRecoveryTime
        self.averageHfStabilityScore = output.summary.aggregate.averageHfStabilityScore
        self.diagnostics = TrainingProbeRunDiagnostics(output: output)
    }
}

public struct TrainingProbeRunDiagnostics: Sendable, Codable, Equatable {
    public let eventCount: Int
    public let driveSampleCount: Int
    public let actuatorSampleCount: Int
    public let averageDriveActivation: Double?
    public let maxDriveActivation: Double?
    public let averageDriveActivationByIndex: [Double]?
    public let maxDriveActivationByIndex: [Double]?
    public let averageActuatorValue: Double?
    public let maxActuatorValue: Double?
    public let averageActuatorValueByIndex: [Double]?
    public let maxActuatorValueByIndex: [Double]?
    public let averageReflexClampMultiplier: Double?
    public let averageReflexDamping: Double?
    public let averageReflexDelta: Double?
    public let averageMotorRawOutput: Double?
    public let averageMotorSaturatedOutput: Double?
    public let averageMotorFinalOutput: Double?
    public let maxMotorFinalOutput: Double?
    public let averageMotorFinalOutputByIndex: [Double]?
    public let maxMotorFinalOutputByIndex: [Double]?
    public let minAltitudeZ: Double?
    public let maxAltitudeZ: Double?
    public let finalAltitudeZ: Double?
    public let minVerticalVelocityZ: Double?
    public let maxVerticalVelocityZ: Double?
    public let finalVerticalVelocityZ: Double?
    public let failureReasons: [String]

    public init(output: TrainingScenarioRunOutput) {
        let events = output.logs.flatMap(\.log.events)
        let driveActivations = events.flatMap { event in
            event.driveIntents.map(\.activation)
        }
        let driveActivationsByIndex = events.flatMap(\.driveIntents).map { drive in
            IndexedDouble(index: Int(drive.index.rawValue), value: drive.activation)
        }
        let actuatorValues = events.flatMap { event in
            event.actuatorValues.map(\.value)
        }
        let actuatorValuesByIndex = events.flatMap(\.actuatorValues).map { actuator in
            IndexedDouble(index: Int(actuator.index.rawValue), value: actuator.value)
        }
        let corrections = events.flatMap(\.reflexCorrections)
        let rawMotorOutputs = events.flatMap { event in
            event.motorNerveTrace?.uRaw ?? []
        }
        let saturatedMotorOutputs = events.flatMap { event in
            event.motorNerveTrace?.uSat ?? []
        }
        let finalMotorOutputs = events.flatMap { event in
            event.motorNerveTrace?.uOut ?? []
        }
        let finalMotorOutputsByIndex = events.flatMap { event in
            (event.motorNerveTrace?.uOut ?? []).enumerated().map { index, value in
                IndexedDouble(index: index, value: value)
            }
        }
        let altitudes = events.map { $0.plantState.root.position.z }
        let verticalVelocities = events.map { $0.plantState.root.velocity.z }
        let evaluationFailures = output.summary.evaluations.flatMap(\.failures)
        let logFailures = output.logs.compactMap { entry in
            entry.log.failureReason?.rawValue
        }

        self.eventCount = events.count
        self.driveSampleCount = driveActivations.count
        self.actuatorSampleCount = actuatorValues.count
        self.averageDriveActivation = Self.average(driveActivations)
        self.maxDriveActivation = driveActivations.max()
        self.averageDriveActivationByIndex = Self.averageByIndex(driveActivationsByIndex)
        self.maxDriveActivationByIndex = Self.maxByIndex(driveActivationsByIndex)
        self.averageActuatorValue = Self.average(actuatorValues)
        self.maxActuatorValue = actuatorValues.max()
        self.averageActuatorValueByIndex = Self.averageByIndex(actuatorValuesByIndex)
        self.maxActuatorValueByIndex = Self.maxByIndex(actuatorValuesByIndex)
        self.averageReflexClampMultiplier = Self.average(corrections.map(\.clampMultiplier))
        self.averageReflexDamping = Self.average(corrections.map(\.damping))
        self.averageReflexDelta = Self.average(corrections.map(\.delta))
        self.averageMotorRawOutput = Self.average(rawMotorOutputs)
        self.averageMotorSaturatedOutput = Self.average(saturatedMotorOutputs)
        self.averageMotorFinalOutput = Self.average(finalMotorOutputs)
        self.maxMotorFinalOutput = finalMotorOutputs.max()
        self.averageMotorFinalOutputByIndex = Self.averageByIndex(finalMotorOutputsByIndex)
        self.maxMotorFinalOutputByIndex = Self.maxByIndex(finalMotorOutputsByIndex)
        self.minAltitudeZ = altitudes.min()
        self.maxAltitudeZ = altitudes.max()
        self.finalAltitudeZ = altitudes.last
        self.minVerticalVelocityZ = verticalVelocities.min()
        self.maxVerticalVelocityZ = verticalVelocities.max()
        self.finalVerticalVelocityZ = verticalVelocities.last
        self.failureReasons = Array(Set(evaluationFailures + logFailures)).sorted()
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func averageByIndex(_ values: [IndexedDouble]) -> [Double]? {
        let grouped = groupedByIndex(values)
        guard !grouped.isEmpty else { return nil }
        return grouped.map { average($0) ?? 0 }
    }

    private static func maxByIndex(_ values: [IndexedDouble]) -> [Double]? {
        let grouped = groupedByIndex(values)
        guard !grouped.isEmpty else { return nil }
        return grouped.map { $0.max() ?? 0 }
    }

    private static func groupedByIndex(_ values: [IndexedDouble]) -> [[Double]] {
        let maxIndex = values.map(\.index).max() ?? -1
        guard maxIndex >= 0 else { return [] }
        var grouped = Array(repeating: [Double](), count: maxIndex + 1)
        for value in values where value.index >= 0 {
            grouped[value.index].append(value.value)
        }
        return grouped
    }

    private struct IndexedDouble {
        let index: Int
        let value: Double
    }
}

public struct TrainingProbeComparison: Sendable, Codable, Equatable {
    public enum SelectedCheckpointRole: String, Sendable, Codable, Equatable {
        case candidate
        case source
        case none
    }

    public let probeID: String
    public let trainingRunID: String
    public let teacherScore: Double
    public let initialScore: Double
    public let trainedScore: Double?
    public let scoreDelta: Double?
    public let trainingAccepted: Bool
    public let checkpointDecision: CheckpointDecisionState
    public let acceptedCheckpointURL: URL?
    public let sourceCheckpointURL: URL?
    public let selectedCheckpointURL: URL?
    public let selectedCheckpointRole: SelectedCheckpointRole
    public let reloadSucceeded: Bool
    public let safetyViolationDelta: Double?
    public let safetyNonRegression: Bool
    public let passedImproved: Bool
    public let meetsMinimumDelta: Bool
    public let teacherPassed: Bool
    public let trainedPassed: Bool
    public let referenceSatisfied: Bool
    public let policySatisfied: Bool
    public let probeAccepted: Bool
    public let probeRejectionReasons: [String]
    public let initialTeacherDriveAverageMAE: Double?
    public let trainedTeacherDriveAverageMAE: Double?
    public let initialTeacherMotorAverageMAE: Double?
    public let trainedTeacherMotorAverageMAE: Double?
    public let initialTeacherFinalAltitudeDelta: Double?
    public let trainedTeacherFinalAltitudeDelta: Double?
    public let teacherDriveDivergenceNonRegression: Bool
    public let teacherMotorDivergenceNonRegression: Bool
    public let teacherAltitudeDivergenceNonRegression: Bool
    public let teacherDivergenceNonRegression: Bool

    public init(
        probeID: String,
        trainingRunID: String,
        teacher: TrainingProbeRunSummary,
        initial: TrainingProbeRunSummary,
        trained: TrainingProbeRunSummary?,
        training: TrainingRunResult,
        minScoreDelta: Double,
        requireTeacherPass: Bool,
        requireTrainedPass: Bool,
        sourceCheckpointURL: URL? = nil
    ) {
        let scoreDelta = trained.map { $0.score - initial.score }
        self.probeID = probeID
        self.trainingRunID = trainingRunID
        self.teacherScore = teacher.score
        self.initialScore = initial.score
        self.trainedScore = trained?.score
        self.scoreDelta = scoreDelta
        self.trainingAccepted = training.convergence.accepted
        self.checkpointDecision = training.checkpointDecision.state
        self.acceptedCheckpointURL = training.checkpointDecision.publishedCheckpointURL
        self.sourceCheckpointURL = sourceCheckpointURL
        self.reloadSucceeded = trained != nil
        self.safetyViolationDelta = trained.map { $0.safetyViolationSeconds - initial.safetyViolationSeconds }
        self.safetyNonRegression = (self.safetyViolationDelta ?? Double.greatestFiniteMagnitude) <= 0
        self.passedImproved = (trained?.suitePassed == true) && !initial.suitePassed
        self.meetsMinimumDelta = (scoreDelta ?? -Double.greatestFiniteMagnitude) >= minScoreDelta
        self.teacherPassed = teacher.suitePassed
        self.trainedPassed = trained?.suitePassed == true
        self.referenceSatisfied = !requireTeacherPass || teacher.suitePassed
        self.policySatisfied = !requireTrainedPass || self.trainedPassed
        self.initialTeacherDriveAverageMAE = Self.meanAbsoluteError(
            initial.diagnostics.averageDriveActivationByIndex,
            teacher.diagnostics.averageDriveActivationByIndex
        )
        self.trainedTeacherDriveAverageMAE = Self.meanAbsoluteError(
            trained?.diagnostics.averageDriveActivationByIndex,
            teacher.diagnostics.averageDriveActivationByIndex
        )
        self.initialTeacherMotorAverageMAE = Self.meanAbsoluteError(
            initial.diagnostics.averageMotorFinalOutputByIndex,
            teacher.diagnostics.averageMotorFinalOutputByIndex
        )
        self.trainedTeacherMotorAverageMAE = Self.meanAbsoluteError(
            trained?.diagnostics.averageMotorFinalOutputByIndex,
            teacher.diagnostics.averageMotorFinalOutputByIndex
        )
        self.initialTeacherFinalAltitudeDelta = Self.delta(
            initial.diagnostics.finalAltitudeZ,
            teacher.diagnostics.finalAltitudeZ
        )
        self.trainedTeacherFinalAltitudeDelta = Self.delta(
            trained?.diagnostics.finalAltitudeZ,
            teacher.diagnostics.finalAltitudeZ
        )
        self.teacherDriveDivergenceNonRegression = Self.nonRegression(
            trained: self.trainedTeacherDriveAverageMAE,
            initial: self.initialTeacherDriveAverageMAE,
            tolerance: 0.01
        )
        self.teacherMotorDivergenceNonRegression = Self.nonRegression(
            trained: self.trainedTeacherMotorAverageMAE,
            initial: self.initialTeacherMotorAverageMAE,
            tolerance: 0.01
        )
        self.teacherAltitudeDivergenceNonRegression = Self.absoluteNonRegression(
            trained: self.trainedTeacherFinalAltitudeDelta,
            initial: self.initialTeacherFinalAltitudeDelta,
            tolerance: 0.25
        )
        self.teacherDivergenceNonRegression = self.teacherDriveDivergenceNonRegression
            && self.teacherMotorDivergenceNonRegression
            && self.teacherAltitudeDivergenceNonRegression

        var rejectionReasons: [String] = []
        if !self.trainingAccepted {
            rejectionReasons.append("training-not-accepted")
        }
        if !self.reloadSucceeded {
            rejectionReasons.append("reload-not-run")
        }
        if !self.meetsMinimumDelta {
            rejectionReasons.append("minimum-delta-not-met")
        }
        if !self.safetyNonRegression {
            rejectionReasons.append("safety-regression")
        }
        if !self.referenceSatisfied {
            rejectionReasons.append("reference-not-satisfied")
        }
        if !self.policySatisfied {
            rejectionReasons.append("policy-not-satisfied")
        }
        if !self.teacherDivergenceNonRegression {
            rejectionReasons.append("teacher-divergence-regression")
        }
        self.probeRejectionReasons = rejectionReasons
        self.probeAccepted = rejectionReasons.isEmpty
        if self.probeAccepted {
            self.selectedCheckpointURL = training.checkpointDecision.publishedCheckpointURL
                ?? training.checkpointDecision.candidateCheckpointURL
            self.selectedCheckpointRole = self.selectedCheckpointURL == nil ? .none : .candidate
        } else if let sourceCheckpointURL {
            self.selectedCheckpointURL = sourceCheckpointURL
            self.selectedCheckpointRole = .source
        } else {
            self.selectedCheckpointURL = nil
            self.selectedCheckpointRole = .none
        }
    }

    private static func meanAbsoluteError(_ lhs: [Double]?, _ rhs: [Double]?) -> Double? {
        guard let lhs, let rhs, !lhs.isEmpty, lhs.count == rhs.count else {
            return nil
        }
        let total = zip(lhs, rhs).reduce(0.0) { partial, pair in
            partial + abs(pair.0 - pair.1)
        }
        return total / Double(lhs.count)
    }

    private static func delta(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs, let rhs else {
            return nil
        }
        return lhs - rhs
    }

    private static func nonRegression(trained: Double?, initial: Double?, tolerance: Double) -> Bool {
        guard let trained, let initial else {
            return true
        }
        return trained <= initial + tolerance
    }

    private static func absoluteNonRegression(trained: Double?, initial: Double?, tolerance: Double) -> Bool {
        guard let trained, let initial else {
            return true
        }
        return abs(trained) <= abs(initial) + tolerance
    }

    public func metricRecords(timestamp: Date = Date()) -> [TrainingMetricRecord] {
        var records: [TrainingMetricRecord] = []
        appendMetric(
            &records,
            kind: .teacherDriveAverageMAE,
            initialValue: initialTeacherDriveAverageMAE,
            trainedValue: trainedTeacherDriveAverageMAE,
            timestamp: timestamp
        )
        appendMetric(
            &records,
            kind: .teacherMotorAverageMAE,
            initialValue: initialTeacherMotorAverageMAE,
            trainedValue: trainedTeacherMotorAverageMAE,
            timestamp: timestamp
        )
        appendMetric(
            &records,
            kind: .teacherFinalAltitudeDelta,
            initialValue: initialTeacherFinalAltitudeDelta,
            trainedValue: trainedTeacherFinalAltitudeDelta,
            timestamp: timestamp
        )
        records.append(TrainingMetricRecord(
            runID: trainingRunID,
            iteration: 1,
            kind: .teacherDivergenceRegression,
            value: teacherDivergenceNonRegression ? 0.0 : 1.0,
            step: 1,
            timestamp: timestamp
        ))
        return records
    }

    private func appendMetric(
        _ records: inout [TrainingMetricRecord],
        kind: TrainingMetricKind,
        initialValue: Double?,
        trainedValue: Double?,
        timestamp: Date
    ) {
        if let initialValue {
            records.append(TrainingMetricRecord(
                runID: trainingRunID,
                iteration: 0,
                kind: kind,
                value: initialValue,
                step: 0,
                timestamp: timestamp
            ))
        }
        if let trainedValue {
            records.append(TrainingMetricRecord(
                runID: trainingRunID,
                iteration: 1,
                kind: kind,
                value: trainedValue,
                step: 1,
                timestamp: timestamp
            ))
        }
    }
}

public struct TrainingProbeResult: Sendable, Equatable {
    public let manifest: TrainingProbeManifest
    public let teacher: TrainingProbeRunSummary
    public let initial: TrainingProbeRunSummary
    public let training: TrainingRunResult
    public let trained: TrainingProbeRunSummary?
    public let comparison: TrainingProbeComparison
    public let probeCheckpointDecision: CheckpointDecision
    public let recoveryRelabelStatus: TrainingProbeRecoveryRelabelStatus

    public init(
        manifest: TrainingProbeManifest,
        teacher: TrainingProbeRunSummary,
        initial: TrainingProbeRunSummary,
        training: TrainingRunResult,
        trained: TrainingProbeRunSummary?,
        comparison: TrainingProbeComparison,
        probeCheckpointDecision: CheckpointDecision,
        recoveryRelabelStatus: TrainingProbeRecoveryRelabelStatus = .skipped(reason: "not-requested")
    ) {
        self.manifest = manifest
        self.teacher = teacher
        self.initial = initial
        self.training = training
        self.trained = trained
        self.comparison = comparison
        self.probeCheckpointDecision = probeCheckpointDecision
        self.recoveryRelabelStatus = recoveryRelabelStatus
    }
}

public struct TrainingProbeRecoveryRelabelStatus: Sendable, Codable, Equatable {
    public let attempted: Bool
    public let datasetDirectory: URL?
    public let report: AttitudeRecoveryRelabelReport?
    public let failureReason: String?

    public init(
        attempted: Bool,
        datasetDirectory: URL?,
        report: AttitudeRecoveryRelabelReport?,
        failureReason: String?
    ) {
        self.attempted = attempted
        self.datasetDirectory = datasetDirectory
        self.report = report
        self.failureReason = failureReason
    }

    public static func skipped(reason: String) -> TrainingProbeRecoveryRelabelStatus {
        TrainingProbeRecoveryRelabelStatus(
            attempted: false,
            datasetDirectory: nil,
            report: nil,
            failureReason: reason
        )
    }
}

@MainActor
public protocol TrainingProbeScenarioExecuting {
    func runProbeSuite(
        stage: TrainingProbeStage,
        request: SimulationRunRequest,
        checkpointURL: URL?
    ) async throws -> TrainingScenarioRunOutput

    func writeRecoveryRelabelDataset(
        output: TrainingScenarioRunOutput,
        request: SimulationRunRequest,
        to directory: URL,
        includeSuccessfulScenarios: Bool
    ) async throws -> AttitudeRecoveryRelabelReport?
}

public extension TrainingProbeScenarioExecuting {
    func writeRecoveryRelabelDataset(
        output: TrainingScenarioRunOutput,
        request: SimulationRunRequest,
        to directory: URL,
        includeSuccessfulScenarios: Bool
    ) async throws -> AttitudeRecoveryRelabelReport? {
        _ = includeSuccessfulScenarios
        return nil
    }
}

@MainActor
public struct TrainingProbeOrchestrator {
    public enum ProbeError: Error, Sendable, Equatable {
        case teacherRunFailed(String)
        case initialRunFailed(String)
        case trainedRunFailed(String)
        case artifactWriteFailed(String)
    }

    public let scenarioExecutor: any TrainingProbeScenarioExecuting
    public let backend: any TrainingBackend
    public let artifactWriter: TrainingProbeArtifactWriter
    public let checkpointRepository: CheckpointRepository

    public init(
        scenarioExecutor: any TrainingProbeScenarioExecuting,
        backend: any TrainingBackend,
        artifactWriter: TrainingProbeArtifactWriter = TrainingProbeArtifactWriter(),
        checkpointRepository: CheckpointRepository = CheckpointRepository()
    ) {
        self.scenarioExecutor = scenarioExecutor
        self.backend = backend
        self.artifactWriter = artifactWriter
        self.checkpointRepository = checkpointRepository
    }

    public func run(
        probeConfig: TrainingProbeConfig,
        teacherRequest: SimulationRunRequest,
        trainingRequest: SimulationRunRequest,
        trainingConfig: TrainingRunConfig,
        trainingTemplate: TrainingBackendRequest,
        artifactDirectory: URL,
        observationMetadata: TrainingObservationMetadata? = nil,
        onTrainingEvent: (@Sendable (TrainingRunEvent) -> Void)? = nil
    ) async -> TrainingProbeResult {
        let startedAt = Date()
        let manifest = TrainingProbeManifest(
            probeID: probeConfig.probeID,
            trainingRunID: trainingConfig.runID,
            startedAt: startedAt,
            terminalState: .running
        )

        let teacher: TrainingProbeRunSummary
        do {
            let output = try await scenarioExecutor.runProbeSuite(
                stage: .teacherActiveAltitudeHold,
                request: teacherRequest,
                checkpointURL: nil
            )
            teacher = TrainingProbeRunSummary(stage: .teacherActiveAltitudeHold, output: output)
        } catch {
            return await failedResult(
                manifest: manifest,
                teacher: nil,
                initial: nil,
                trainingConfig: trainingConfig,
                artifactDirectory: artifactDirectory,
                reason: "teacher-run-failed: \(error)"
            )
        }

        let initial: TrainingProbeRunSummary
        do {
            let output = try await scenarioExecutor.runProbeSuite(
                stage: .initialPolicy,
                request: trainingRequest,
                checkpointURL: trainingTemplate.sourceSnapshot?.checkpointURL
            )
            initial = TrainingProbeRunSummary(stage: .initialPolicy, output: output)
        } catch {
            return await failedResult(
                manifest: manifest,
                teacher: teacher,
                initial: nil,
                trainingConfig: trainingConfig,
                artifactDirectory: artifactDirectory,
                reason: "initial-run-failed: \(error)"
            )
        }

        let trainingDirectory = artifactDirectory.appendingPathComponent("training", isDirectory: true)
        let training = await TrainingRunOrchestrator(
            scenarioExecutor: ProbeTrainingScenarioAdapter(
                executor: scenarioExecutor,
                checkpointURL: trainingTemplate.sourceSnapshot?.checkpointURL
            ),
            backend: backend
        ).run(
            config: trainingConfig.withCheckpointPublicationMode(.deferred),
            runRequest: trainingRequest,
            trainingTemplate: trainingTemplate,
            artifactDirectory: trainingDirectory,
            observationMetadata: observationMetadata,
            onEvent: onTrainingEvent
        )

        var trained: TrainingProbeRunSummary?
        var trainedOutput: TrainingScenarioRunOutput?
        let evaluationCheckpointURL = training.checkpointDecision.publishedCheckpointURL
            ?? training.checkpointDecision.candidateCheckpointURL
        if training.convergence.accepted || !probeConfig.requireAcceptedCheckpoint {
            do {
                let output = try await scenarioExecutor.runProbeSuite(
                    stage: .trainedPolicy,
                    request: trainingRequest,
                    checkpointURL: evaluationCheckpointURL
                )
                trainedOutput = output
                trained = TrainingProbeRunSummary(stage: .trainedPolicy, output: output)
            } catch {
                return await failedResult(
                    manifest: manifest,
                    teacher: teacher,
                    initial: initial,
                    training: training,
                    artifactDirectory: artifactDirectory,
                    reason: "trained-run-failed: \(error)"
                )
            }
        }

        let comparison = TrainingProbeComparison(
            probeID: probeConfig.probeID,
            trainingRunID: trainingConfig.runID,
            teacher: teacher,
            initial: initial,
            trained: trained,
            training: training,
            minScoreDelta: probeConfig.minScoreDelta,
            requireTeacherPass: probeConfig.requireTeacherPass,
            requireTrainedPass: probeConfig.requireTrainedPass,
            sourceCheckpointURL: trainingTemplate.sourceSnapshot?.checkpointURL
        )
        let probeCheckpointDecision = finalizeProbeCheckpoint(
            training: training,
            comparison: comparison,
            trainingDirectory: trainingDirectory
        )
        let recoveryRelabelStatus = await makeRecoveryRelabelStatus(
            comparison: comparison,
            trainedOutput: trainedOutput,
            trainingRequest: trainingRequest,
            artifactDirectory: artifactDirectory
        )
        let terminalState = comparison.probeAccepted
            ? LearningRunTerminalState.completed
            : LearningRunTerminalState.rejected
        let completedManifest = manifest.completed(
            at: Date(),
            terminalState: terminalState,
            failureReason: terminalState == .completed ? nil : comparison.probeRejectionReasons.joined(separator: ",")
        )
        let result = TrainingProbeResult(
            manifest: completedManifest,
            teacher: teacher,
            initial: initial,
            training: training,
            trained: trained,
            comparison: comparison,
            probeCheckpointDecision: probeCheckpointDecision,
            recoveryRelabelStatus: recoveryRelabelStatus
        )
        do {
            try artifactWriter.write(result: result, to: artifactDirectory)
        } catch {
            return TrainingProbeResult(
                manifest: completedManifest.completed(
                    at: Date(),
                    terminalState: .failed,
                    failureReason: "probe-artifact-write-failed: \(error)"
                ),
                teacher: teacher,
                initial: initial,
                training: training,
                trained: trained,
                comparison: comparison,
                probeCheckpointDecision: probeCheckpointDecision,
                recoveryRelabelStatus: recoveryRelabelStatus
            )
        }
        return result
    }

    private func failedResult(
        manifest: TrainingProbeManifest,
        teacher: TrainingProbeRunSummary?,
        initial: TrainingProbeRunSummary?,
        trainingConfig: TrainingRunConfig,
        artifactDirectory: URL,
        reason: String
    ) async -> TrainingProbeResult {
        let training = emptyTrainingResult(runID: trainingConfig.runID, reason: reason)
        return await failedResult(
            manifest: manifest,
            teacher: teacher,
            initial: initial,
            training: training,
            artifactDirectory: artifactDirectory,
            reason: reason
        )
    }

    private func failedResult(
        manifest: TrainingProbeManifest,
        teacher: TrainingProbeRunSummary?,
        initial: TrainingProbeRunSummary?,
        training: TrainingRunResult,
        artifactDirectory: URL,
        reason: String
    ) async -> TrainingProbeResult {
        let fallbackTeacher = teacher ?? TrainingProbeRunSummary.empty(stage: .teacherActiveAltitudeHold)
        let fallbackInitial = initial ?? TrainingProbeRunSummary.empty(stage: .initialPolicy)
        let comparison = TrainingProbeComparison(
            probeID: manifest.probeID,
            trainingRunID: manifest.trainingRunID,
            teacher: fallbackTeacher,
            initial: fallbackInitial,
            trained: nil,
            training: training,
            minScoreDelta: 0,
            requireTeacherPass: true,
            requireTrainedPass: true
        )
        let probeCheckpointDecision = CheckpointDecision(
            runID: training.manifest.runID,
            state: .skipped,
            reason: reason,
            candidateCheckpointID: training.checkpointDecision.candidateCheckpointID,
            candidateCheckpointURL: training.checkpointDecision.candidateCheckpointURL,
            publishedCheckpointURL: nil
        )
        let failedManifest = manifest.completed(at: Date(), terminalState: .failed, failureReason: reason)
        let result = TrainingProbeResult(
            manifest: failedManifest,
            teacher: fallbackTeacher,
            initial: fallbackInitial,
            training: training,
            trained: nil,
            comparison: comparison,
            probeCheckpointDecision: probeCheckpointDecision
        )
        do {
            try artifactWriter.write(result: result, to: artifactDirectory)
        } catch {
            return TrainingProbeResult(
                manifest: failedManifest.completed(
                    at: Date(),
                    terminalState: .failed,
                    failureReason: "probe-artifact-write-failed: \(error)"
                ),
                teacher: fallbackTeacher,
                initial: fallbackInitial,
                training: training,
                trained: nil,
                comparison: comparison,
                probeCheckpointDecision: probeCheckpointDecision
            )
        }
        return result
    }

    private func emptyTrainingResult(runID: String, reason: String) -> TrainingRunResult {
        let convergence = ConvergenceSummary(
            runID: runID,
            accepted: false,
            reason: reason,
            passRate: 0,
            failureRate: 1,
            safetyRegressionDetected: false,
            plateauDetected: false,
            overfitRiskDetected: false
        )
        return TrainingRunResult(
            manifest: LearningRunManifest(
                runID: runID,
                mode: .supervised,
                configHash: "probe-unstarted",
                suiteID: "probe",
                seedSet: [],
                policyID: "probe",
                workerCount: 1,
                startedAt: Date(),
                completedAt: Date(),
                terminalState: .failed,
                failureReason: reason
            ),
            metrics: [],
            convergence: convergence,
            checkpointDecision: CheckpointDecision(
                runID: runID,
                state: .skipped,
                reason: reason,
                candidateCheckpointID: nil,
                candidateCheckpointURL: nil,
                publishedCheckpointURL: nil
            )
        )
    }

    private func finalizeProbeCheckpoint(
        training: TrainingRunResult,
        comparison: TrainingProbeComparison,
        trainingDirectory: URL
    ) -> CheckpointDecision {
        guard let candidateCheckpointID = training.checkpointDecision.candidateCheckpointID else {
            return CheckpointDecision(
                runID: training.manifest.runID,
                state: .skipped,
                reason: "no-candidate-checkpoint",
                candidateCheckpointID: nil,
                candidateCheckpointURL: training.checkpointDecision.candidateCheckpointURL,
                publishedCheckpointURL: nil
            )
        }
        let accepted = comparison.probeAccepted
        let initial = CheckpointDecision(
            runID: training.manifest.runID,
            state: accepted ? .accepted : .rejected,
            reason: accepted ? "probe-accepted" : "probe-rejected",
            candidateCheckpointID: candidateCheckpointID,
            candidateCheckpointURL: training.checkpointDecision.candidateCheckpointURL,
            publishedCheckpointURL: nil
        )
        do {
            return try checkpointRepository.publish(decision: initial, under: trainingDirectory)
        } catch {
            return CheckpointDecision(
                runID: training.manifest.runID,
                state: .failed,
                reason: "probe-checkpoint-publish-failed: \(error)",
                candidateCheckpointID: candidateCheckpointID,
                candidateCheckpointURL: training.checkpointDecision.candidateCheckpointURL,
                publishedCheckpointURL: nil
            )
        }
    }

    private func makeRecoveryRelabelStatus(
        comparison: TrainingProbeComparison,
        trainedOutput: TrainingScenarioRunOutput?,
        trainingRequest: SimulationRunRequest,
        artifactDirectory: URL
    ) async -> TrainingProbeRecoveryRelabelStatus {
        guard !comparison.probeAccepted else {
            return .skipped(reason: "probe-accepted")
        }
        guard let trainedOutput else {
            return .skipped(reason: "trained-output-unavailable")
        }
        let includeSuccessfulScenarios = !comparison.teacherDivergenceNonRegression
            || !comparison.policySatisfied
        let directory = artifactDirectory.appendingPathComponent("recovery-datasets", isDirectory: true)
        do {
            guard let report = try await scenarioExecutor.writeRecoveryRelabelDataset(
                output: trainedOutput,
                request: trainingRequest,
                to: directory,
                includeSuccessfulScenarios: includeSuccessfulScenarios
            ) else {
                return .skipped(reason: "recovery-relabel-unavailable")
            }
            guard report.relabeledEntryCount > 0 else {
                return .skipped(reason: "recovery-relabel-empty")
            }
            return TrainingProbeRecoveryRelabelStatus(
                attempted: true,
                datasetDirectory: directory,
                report: report,
                failureReason: nil
            )
        } catch {
            return TrainingProbeRecoveryRelabelStatus(
                attempted: true,
                datasetDirectory: directory,
                report: nil,
                failureReason: "recovery-relabel-failed: \(error)"
            )
        }
    }
}

public struct TrainingProbeArtifactWriter: Sendable {
    public init() {}

    public func write(result: TrainingProbeResult, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(result.manifest).write(
            to: directory.appendingPathComponent("probe-manifest.json"),
            options: [.atomic]
        )
        try encoder.encode(result.teacher).write(
            to: directory.appendingPathComponent("teacher-run.json"),
            options: [.atomic]
        )
        try encoder.encode(result.initial).write(
            to: directory.appendingPathComponent("initial-run.json"),
            options: [.atomic]
        )
        if let trained = result.trained {
            try encoder.encode(trained).write(
                to: directory.appendingPathComponent("trained-run.json"),
                options: [.atomic]
            )
        }
        try encoder.encode(result.comparison).write(
            to: directory.appendingPathComponent("comparison.json"),
            options: [.atomic]
        )
        try writeProbeMetrics(result.comparison.metricRecords(), to: directory)
        try encoder.encode(result.probeCheckpointDecision).write(
            to: directory.appendingPathComponent("probe-checkpoint-decision.json"),
            options: [.atomic]
        )
        try encoder.encode(result.recoveryRelabelStatus).write(
            to: directory.appendingPathComponent("recovery-relabel-status.json"),
            options: [.atomic]
        )
    }

    private func writeProbeMetrics(_ metrics: [TrainingMetricRecord], to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let records = try metrics.map { record in
            let data = try encoder.encode(record)
            guard let line = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return line
        }
        try (records.joined(separator: "\n") + (records.isEmpty ? "" : "\n")).write(
            to: directory.appendingPathComponent("probe-metrics.jsonl"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private extension TrainingRunConfig {
    func withCheckpointPublicationMode(_ mode: TrainingRunConfig.CheckpointPublicationMode) -> TrainingRunConfig {
        TrainingRunConfig(
            runID: runID,
            mode: self.mode,
            maxIterations: maxIterations,
            minDelta: minDelta,
            workerCount: workerCount,
            enableDatasetExport: enableDatasetExport,
            enableTraining: enableTraining,
            stopOnPass: stopOnPass,
            parentCheckpointID: parentCheckpointID,
            policyID: policyID,
            parallelWorkerPlan: parallelWorkerPlan,
            checkpointPublicationMode: mode
        )
    }
}

private extension TrainingProbeRunSummary {
    static func empty(stage: TrainingProbeStage) -> TrainingProbeRunSummary {
        TrainingProbeRunSummary(
            stage: stage,
            score: -Double.greatestFiniteMagnitude,
            suitePassed: false,
            scenarioCount: 0,
            safetyViolationSeconds: Double.greatestFiniteMagnitude,
            worstOvershootDegrees: nil,
            averageRecoveryTime: nil,
            averageHfStabilityScore: nil,
            diagnostics: TrainingProbeRunDiagnostics.empty
        )
    }

    init(
        stage: TrainingProbeStage,
        score: Double,
        suitePassed: Bool,
        scenarioCount: Int,
        safetyViolationSeconds: Double,
        worstOvershootDegrees: Double?,
        averageRecoveryTime: Double?,
        averageHfStabilityScore: Double?,
        diagnostics: TrainingProbeRunDiagnostics
    ) {
        self.stage = stage
        self.score = score
        self.suitePassed = suitePassed
        self.scenarioCount = scenarioCount
        self.safetyViolationSeconds = safetyViolationSeconds
        self.worstOvershootDegrees = worstOvershootDegrees
        self.averageRecoveryTime = averageRecoveryTime
        self.averageHfStabilityScore = averageHfStabilityScore
        self.diagnostics = diagnostics
    }
}

private extension TrainingProbeRunDiagnostics {
    static var empty: TrainingProbeRunDiagnostics {
        TrainingProbeRunDiagnostics(
            eventCount: 0,
            driveSampleCount: 0,
            actuatorSampleCount: 0,
            averageDriveActivation: nil,
            maxDriveActivation: nil,
            averageDriveActivationByIndex: nil,
            maxDriveActivationByIndex: nil,
            averageActuatorValue: nil,
            maxActuatorValue: nil,
            averageActuatorValueByIndex: nil,
            maxActuatorValueByIndex: nil,
            averageReflexClampMultiplier: nil,
            averageReflexDamping: nil,
            averageReflexDelta: nil,
            averageMotorRawOutput: nil,
            averageMotorSaturatedOutput: nil,
            averageMotorFinalOutput: nil,
            maxMotorFinalOutput: nil,
            averageMotorFinalOutputByIndex: nil,
            maxMotorFinalOutputByIndex: nil,
            minAltitudeZ: nil,
            maxAltitudeZ: nil,
            finalAltitudeZ: nil,
            minVerticalVelocityZ: nil,
            maxVerticalVelocityZ: nil,
            finalVerticalVelocityZ: nil,
            failureReasons: []
        )
    }

    init(
        eventCount: Int,
        driveSampleCount: Int,
        actuatorSampleCount: Int,
        averageDriveActivation: Double?,
        maxDriveActivation: Double?,
        averageDriveActivationByIndex: [Double]?,
        maxDriveActivationByIndex: [Double]?,
        averageActuatorValue: Double?,
        maxActuatorValue: Double?,
        averageActuatorValueByIndex: [Double]?,
        maxActuatorValueByIndex: [Double]?,
        averageReflexClampMultiplier: Double?,
        averageReflexDamping: Double?,
        averageReflexDelta: Double?,
        averageMotorRawOutput: Double?,
        averageMotorSaturatedOutput: Double?,
        averageMotorFinalOutput: Double?,
        maxMotorFinalOutput: Double?,
        averageMotorFinalOutputByIndex: [Double]?,
        maxMotorFinalOutputByIndex: [Double]?,
        minAltitudeZ: Double?,
        maxAltitudeZ: Double?,
        finalAltitudeZ: Double?,
        minVerticalVelocityZ: Double?,
        maxVerticalVelocityZ: Double?,
        finalVerticalVelocityZ: Double?,
        failureReasons: [String]
    ) {
        self.eventCount = eventCount
        self.driveSampleCount = driveSampleCount
        self.actuatorSampleCount = actuatorSampleCount
        self.averageDriveActivation = averageDriveActivation
        self.maxDriveActivation = maxDriveActivation
        self.averageDriveActivationByIndex = averageDriveActivationByIndex
        self.maxDriveActivationByIndex = maxDriveActivationByIndex
        self.averageActuatorValue = averageActuatorValue
        self.maxActuatorValue = maxActuatorValue
        self.averageActuatorValueByIndex = averageActuatorValueByIndex
        self.maxActuatorValueByIndex = maxActuatorValueByIndex
        self.averageReflexClampMultiplier = averageReflexClampMultiplier
        self.averageReflexDamping = averageReflexDamping
        self.averageReflexDelta = averageReflexDelta
        self.averageMotorRawOutput = averageMotorRawOutput
        self.averageMotorSaturatedOutput = averageMotorSaturatedOutput
        self.averageMotorFinalOutput = averageMotorFinalOutput
        self.maxMotorFinalOutput = maxMotorFinalOutput
        self.averageMotorFinalOutputByIndex = averageMotorFinalOutputByIndex
        self.maxMotorFinalOutputByIndex = maxMotorFinalOutputByIndex
        self.minAltitudeZ = minAltitudeZ
        self.maxAltitudeZ = maxAltitudeZ
        self.finalAltitudeZ = finalAltitudeZ
        self.minVerticalVelocityZ = minVerticalVelocityZ
        self.maxVerticalVelocityZ = maxVerticalVelocityZ
        self.finalVerticalVelocityZ = finalVerticalVelocityZ
        self.failureReasons = failureReasons
    }
}

@MainActor
private final class ProbeTrainingScenarioAdapter: TrainingScenarioExecuting {
    private let executor: any TrainingProbeScenarioExecuting
    private let checkpointURL: URL?

    init(executor: any TrainingProbeScenarioExecuting, checkpointURL: URL?) {
        self.executor = executor
        self.checkpointURL = checkpointURL
    }

    func runSuiteForTrainingRun(request: SimulationRunRequest) async throws -> TrainingScenarioRunOutput {
        try await executor.runProbeSuite(
            stage: .trainingIteration,
            request: request,
            checkpointURL: checkpointURL
        )
    }
}
