import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTrainingContracts

public struct RunnableStarterScenarioArtifactReport: Sendable, Codable, Equatable {
    public static let fileName = "runnable-starter-scenario-artifacts.json"

    public let generatedAt: Date
    public let artifacts: [RunnableStarterScenarioArtifactRecord]

    public init(
        generatedAt: Date,
        artifacts: [RunnableStarterScenarioArtifactRecord]
    ) {
        self.generatedAt = generatedAt
        self.artifacts = artifacts
    }
}

public struct RunnableStarterScenarioArtifactRecord: Sendable, Codable, Equatable {
    public let templateID: String
    public let stageID: String
    public let task: String
    public let taskProfileID: String
    public let runID: String
    public let artifactDirectory: URL
    public let suiteIDs: [Int]
    public let scenarioCount: Int
    public let replayCheckCount: Int
    public let passedEvaluationCount: Int
    public let suitePassed: Bool

    public init(
        templateID: String,
        stageID: String,
        task: String,
        taskProfileID: String,
        runID: String,
        artifactDirectory: URL,
        suiteIDs: [Int],
        scenarioCount: Int,
        replayCheckCount: Int,
        passedEvaluationCount: Int,
        suitePassed: Bool
    ) {
        self.templateID = templateID
        self.stageID = stageID
        self.task = task
        self.taskProfileID = taskProfileID
        self.runID = runID
        self.artifactDirectory = artifactDirectory
        self.suiteIDs = suiteIDs
        self.scenarioCount = scenarioCount
        self.replayCheckCount = replayCheckCount
        self.passedEvaluationCount = passedEvaluationCount
        self.suitePassed = suitePassed
    }
}

public struct RunnableStarterScenarioArtifactGenerator: Sendable {
    public enum GenerationError: Error, Sendable, Equatable, CustomStringConvertible {
        case noRunnableStarterTemplates
        case missingPrimaryStage(templateID: String)
        case missingTaskProfile(templateID: String, stageID: String)
        case unsupportedProfileTask(templateID: String, stageID: String, task: String)

        public var description: String {
            switch self {
            case .noRunnableStarterTemplates:
                return "no-runnable-starter-templates"
            case .missingPrimaryStage(let templateID):
                return "missing-primary-stage template=\(templateID)"
            case .missingTaskProfile(let templateID, let stageID):
                return "missing-task-profile template=\(templateID) stage=\(stageID)"
            case .unsupportedProfileTask(let templateID, let stageID, let task):
                return "unsupported-profile-task template=\(templateID) stage=\(stageID) task=\(task)"
            }
        }
    }

    public init() {}

    public func generate(
        catalog: LearningProjectTemplateCatalog = LearningProjectTemplateCatalog(),
        to outputRoot: URL,
        generatedAt: Date = Date()
    ) async throws -> RunnableStarterScenarioArtifactReport {
        let starters = catalog.templates.filter(\.isRunnableStarter)
        guard !starters.isEmpty else {
            throw GenerationError.noRunnableStarterTemplates
        }

        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        var records: [RunnableStarterScenarioArtifactRecord] = []
        for template in starters {
            records.append(try await generate(template: template, outputRoot: outputRoot, generatedAt: generatedAt))
        }

        let report = RunnableStarterScenarioArtifactReport(generatedAt: generatedAt, artifacts: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(
            to: outputRoot.appendingPathComponent(RunnableStarterScenarioArtifactReport.fileName),
            options: [.atomic]
        )
        return report
    }

    private func generate(
        template: LearningProjectTemplate,
        outputRoot: URL,
        generatedAt: Date
    ) async throws -> RunnableStarterScenarioArtifactRecord {
        try RunnableStarterScenarioCoverageValidator().validate(template)
        guard let stage = template.primaryRunnableTrainingStage else {
            throw GenerationError.missingPrimaryStage(templateID: template.templateID)
        }
        guard let taskProfileID = stage.taskProfileID ?? template.taskProfileID else {
            throw GenerationError.missingTaskProfile(templateID: template.templateID, stageID: stage.stageID)
        }
        let profile = try TaskEvaluationProfile.profile(profileID: taskProfileID)
        let taskMode = try taskMode(for: profile, template: template, stage: stage)
        let runID = sanitizedRunID(templateID: template.templateID, stageID: stage.stageID)
        let artifactDirectory = outputRoot.appendingPathComponent(runID, isDirectory: true)
        let request = try request(
            template: template,
            stage: stage,
            taskMode: taskMode
        )
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: request.cutPeriodSteps)
        let runtime = ReferenceQuadrotorBaselineReplayRuntime()

        var scenarioRuns: [TrainingScenarioRunArtifact] = []
        var metrics: [TrainingMetricRecord] = []
        var allEvaluations: [TrainingScenarioEvaluationRecord] = []
        var allReplayCheckCount = 0

        let episodeCount = stage.seedCount * stage.episodesPerSuite
        for (index, suiteID) in stage.suiteIDs.enumerated() {
            let definitions = try ReferenceQuadrotorScenarioCatalog.scenarios(
                for: taskMode,
                suite: suiteID,
                episodeCount: episodeCount
            )
            let output = try await runtime.run(
                request: request,
                parameters: ReferenceQuadrotorParameters.baseline,
                schedule: schedule,
                definitions: definitions
            )
            let iteration = index + 1
            let trainingOutput = TrainingScenarioRunOutput(kuyAtt1: output)
            try TrainingScenarioReplayValidator().validate(trainingOutput)
            scenarioRuns.append(TrainingScenarioRunArtifact(
                runID: runID,
                iteration: iteration,
                output: trainingOutput
            ))
            metrics.append(contentsOf: Self.metrics(
                runID: runID,
                iteration: iteration,
                output: trainingOutput,
                timestamp: generatedAt
            ))
            allEvaluations.append(contentsOf: trainingOutput.summary.evaluations)
            allReplayCheckCount += trainingOutput.summary.replay.checks.count
        }

        let passRate = Self.passRate(evaluations: allEvaluations)
        let failureRate = 1.0 - passRate
        let convergence = ConvergenceSummary(
            runID: runID,
            accepted: false,
            reason: "scenario-replay-evidence-only-no-checkpoint",
            passRate: passRate,
            failureRate: failureRate,
            safetyRegressionDetected: false,
            plateauDetected: false,
            overfitRiskDetected: false
        )
        let manifest = LearningRunManifest(
            runID: runID,
            mode: .supervised,
            robotManifestID: template.robotManifest.robotManifestID,
            configHash: configHash(template: template, stage: stage),
            suiteID: stage.suiteIDs.map(String.init).joined(separator: ","),
            seedSet: allEvaluations.map(\.seed.rawValue),
            policyID: "baseline-replay",
            outputCheckpointID: nil,
            workerCount: 1,
            startedAt: generatedAt,
            completedAt: generatedAt,
            terminalState: .completed,
            failureReason: nil
        )
        let checkpointDecision = CheckpointDecision(
            runID: runID,
            state: .skipped,
            reason: "scenario-replay-evidence-only-no-checkpoint",
            decidedAt: generatedAt
        )
        try TrainingArtifactWriter().write(
            manifest: manifest,
            metrics: metrics,
            convergence: convergence,
            checkpointDecision: checkpointDecision,
            scenarioRuns: scenarioRuns,
            to: artifactDirectory
        )
        _ = try TrainingRunArtifactValidator().loadAndValidate(from: artifactDirectory)

        return RunnableStarterScenarioArtifactRecord(
            templateID: template.templateID,
            stageID: stage.stageID,
            task: stage.task,
            taskProfileID: taskProfileID,
            runID: runID,
            artifactDirectory: artifactDirectory,
            suiteIDs: stage.suiteIDs,
            scenarioCount: allEvaluations.count,
            replayCheckCount: allReplayCheckCount,
            passedEvaluationCount: allEvaluations.filter(\.passed).count,
            suitePassed: scenarioRuns.allSatisfy(\.summary.suitePassed)
        )
    }

    private func request(
        template: LearningProjectTemplate,
        stage: LearningProjectTrainingStage,
        taskMode: SimulationTaskMode
    ) throws -> SimulationRunRequest {
        SimulationRunRequest(
            controller: .teacherActiveAltitudeHold,
            taskMode: taskMode,
            gains: try ImuRateDampingCutGains(kp: 6.0, kd: 4.0, yawDamping: 0.4, hoverThrustScale: 1.0),
            cutPeriodSteps: 2,
            noise: .zero,
            determinism: .tier1Baseline,
            robotManifestPath: template.robotManifest.path ?? template.robotManifest.robotManifestID,
            overrideParameters: nil,
            useAux: false,
            useQualityGating: true
        )
    }

    private func taskMode(
        for profile: TaskEvaluationProfile,
        template: LearningProjectTemplate,
        stage: LearningProjectTrainingStage
    ) throws -> SimulationTaskMode {
        switch profile.task {
        case "attitude":
            return .attitude
        case "lift":
            return .lift
        case "singleLift":
            return .singleLift
        default:
            throw GenerationError.unsupportedProfileTask(
                templateID: template.templateID,
                stageID: stage.stageID,
                task: profile.task
            )
        }
    }

    private func sanitizedRunID(templateID: String, stageID: String) -> String {
        let raw = "\(templateID)-\(stageID)-scenario-replay"
        let characters = raw.map { character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return character
            }
            return "-"
        }
        return String(characters)
    }

    private func configHash(template: LearningProjectTemplate, stage: LearningProjectTrainingStage) -> String {
        [
            template.templateID,
            stage.stageID,
            stage.task,
            stage.suiteIDs.map(String.init).joined(separator: ","),
            "\(stage.seedCount)",
            "\(stage.episodesPerSuite)",
        ].joined(separator: "|")
    }

    private static func metrics(
        runID: String,
        iteration: Int,
        output: TrainingScenarioRunOutput,
        timestamp: Date
    ) -> [TrainingMetricRecord] {
        let evaluations = output.summary.evaluations
        let total = max(evaluations.count, 1)
        let passed = evaluations.filter(\.passed).count
        let failures = evaluations.filter { !$0.passed || $0.failureReason != nil }.count
        let safetyViolation = evaluations.reduce(0.0) { partial, evaluation in
            partial + evaluation.sustainedViolationSeconds
        }
        return [
            TrainingMetricRecord(
                runID: runID,
                iteration: iteration,
                kind: .score,
                value: output.summary.suitePassed ? 1.0 : 0.0,
                timestamp: timestamp
            ),
            TrainingMetricRecord(
                runID: runID,
                iteration: iteration,
                kind: .passRate,
                value: Double(passed) / Double(total),
                timestamp: timestamp
            ),
            TrainingMetricRecord(
                runID: runID,
                iteration: iteration,
                kind: .failureRate,
                value: Double(failures) / Double(total),
                timestamp: timestamp
            ),
            TrainingMetricRecord(
                runID: runID,
                iteration: iteration,
                kind: .safetyViolation,
                value: safetyViolation,
                timestamp: timestamp
            ),
        ]
    }

    private static func passRate(evaluations: [TrainingScenarioEvaluationRecord]) -> Double {
        guard !evaluations.isEmpty else { return 0.0 }
        let passed = evaluations.filter(\.passed).count
        return Double(passed) / Double(evaluations.count)
    }
}
