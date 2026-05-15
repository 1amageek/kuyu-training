import Foundation
import Testing
@testable import KuyuTraining

@Test(.timeLimit(.minutes(1))) func defaultAutonomyPlansValidateForVehicleRobotAndDroneDomains() throws {
    let factory = AutonomousTrainingPipelineFactory()
    let validator = AutonomousTrainingPipelineValidator()

    for domain in [AutonomousOperationDomain.automotive, .groundRobot, .aerialDrone, .manipulator] {
        let plan = factory.defaultPlan(domain: domain, taskProfileIDs: ["lift-v1"])
        try validator.validate(plan)
        #expect(plan.stages.contains { $0.kind == .evolution })
    }
}

@Test(.timeLimit(.minutes(1))) func droneAutonomyPlanRequiresHardwareBoundaryGate() throws {
    let plan = AutonomousTrainingPipelineFactory().defaultPlan(domain: .aerialDrone, taskProfileIDs: ["lift-v1"])

    #expect(plan.terminalGates.contains(.hardwareBoundaryValidated))
    #expect(plan.stages.contains { $0.kind == .hardwareInTheLoop })
    #expect(plan.stages.contains { $0.kind == .evolution })
}

@Test(.timeLimit(.minutes(1))) func autonomyPlansUseReinforcementBeforeEvolutionBeforeStressOrder() throws {
    let factory = AutonomousTrainingPipelineFactory()

    for domain in [AutonomousOperationDomain.automotive, .groundRobot, .aerialDrone, .manipulator] {
        let plan = factory.defaultPlan(domain: domain, taskProfileIDs: ["autonomy-v1"])
        let reinforcementIndex = try #require(plan.stages.firstIndex { $0.kind == .reinforcement })
        let evolutionIndex = try #require(plan.stages.firstIndex { $0.kind == .evolution })
        let stressIndex = try #require(plan.stages.firstIndex { $0.kind == .stress })
        #expect(reinforcementIndex < evolutionIndex)
        #expect(evolutionIndex < stressIndex)
    }
}

@Test(.timeLimit(.minutes(1))) func autonomyPipelineRejectsMissingRecoveryCapability() throws {
    let plan = AutonomousTrainingPipelinePlan(
        planID: "bad-automotive",
        domain: .automotive,
        targetCapabilities: [.sensorIngestion],
        stages: [
            AutonomousTrainingStagePlan(
                stageID: "imitation",
                kind: .imitation,
                taskProfileIDs: ["drive-v1"],
                capabilities: [.sensorIngestion],
                requiredExitGates: [.modelBundleValidated],
                producesModelBundle: true
            ),
            AutonomousTrainingStagePlan(
                stageID: "reinforcement",
                kind: .reinforcement,
                taskProfileIDs: ["drive-v1"],
                capabilities: [.trajectoryTracking],
                requiredExitGates: [.scenarioRegressionPassed],
                producesModelBundle: true
            ),
            AutonomousTrainingStagePlan(
                stageID: "world-model",
                kind: .worldModel,
                taskProfileIDs: ["drive-v1"],
                capabilities: [.stateEstimation],
                requiredExitGates: [.telemetryComplete],
                producesModelBundle: true
            ),
            AutonomousTrainingStagePlan(
                stageID: "stress",
                kind: .stress,
                taskProfileIDs: ["drive-v1"],
                capabilities: [.faultDetection],
                requiredExitGates: [.stressRegressionPassed],
                producesModelBundle: true
            ),
            AutonomousTrainingStagePlan(
                stageID: "regression",
                kind: .regression,
                taskProfileIDs: ["drive-v1"],
                capabilities: [.safeStop, .humanTakeover],
                requiredExitGates: [.scenarioRegressionPassed],
                producesModelBundle: false
            ),
            AutonomousTrainingStagePlan(
                stageID: "closed-course",
                kind: .closedCourse,
                taskProfileIDs: ["drive-v1"],
                capabilities: [.missionExecution, .obstacleAvoidance],
                requiredExitGates: [.scenarioRegressionPassed],
                producesModelBundle: false
            )
        ],
        terminalGates: AutonomousTrainingPipelineValidator.requiredTerminalGates(for: .automotive)
    )

    #expect(throws: AutonomousTrainingPipelineValidationError.missingRequiredCapability(.recoveryBehavior)) {
        try AutonomousTrainingPipelineValidator().validate(plan)
    }
}

@Test(.timeLimit(.minutes(1))) func autonomyPipelineRejectsStressAfterRegressionOrder() throws {
    let factory = AutonomousTrainingPipelineFactory()
    let valid = factory.defaultPlan(domain: .groundRobot, taskProfileIDs: ["navigation-v1"])
    let swappedStages = valid.stages.map { stage -> AutonomousTrainingStagePlan in
        if stage.kind == .stress {
            return AutonomousTrainingStagePlan(
                stageID: stage.stageID,
                kind: .regression,
                taskProfileIDs: stage.taskProfileIDs,
                capabilities: stage.capabilities,
                requiredEntryGates: stage.requiredEntryGates,
                requiredExitGates: stage.requiredExitGates,
                producesModelBundle: stage.producesModelBundle
            )
        }
        if stage.kind == .regression {
            return AutonomousTrainingStagePlan(
                stageID: stage.stageID,
                kind: .stress,
                taskProfileIDs: stage.taskProfileIDs,
                capabilities: stage.capabilities,
                requiredEntryGates: stage.requiredEntryGates,
                requiredExitGates: stage.requiredExitGates,
                producesModelBundle: stage.producesModelBundle
            )
        }
        return stage
    }
    let invalid = AutonomousTrainingPipelinePlan(
        planID: valid.planID,
        domain: valid.domain,
        targetCapabilities: valid.targetCapabilities,
        stages: swappedStages,
        terminalGates: valid.terminalGates
    )

    #expect(throws: AutonomousTrainingPipelineValidationError.stageOrderViolation(
        requiredBefore: .stress,
        requiredAfter: .regression
    )) {
        try AutonomousTrainingPipelineValidator().validate(invalid)
    }
}

@Test(.timeLimit(.minutes(1))) func autonomyPipelineRejectsMissingTerminalSafetyGate() throws {
    let valid = AutonomousTrainingPipelineFactory().defaultPlan(domain: .aerialDrone, taskProfileIDs: ["lift-v1"])
    let invalid = AutonomousTrainingPipelinePlan(
        planID: valid.planID,
        domain: valid.domain,
        targetCapabilities: valid.targetCapabilities,
        stages: valid.stages,
        terminalGates: valid.terminalGates.filter { $0 != .humanTakeoverValidated }
    )

    #expect(throws: AutonomousTrainingPipelineValidationError.missingRequiredTerminalGate(.humanTakeoverValidated)) {
        try AutonomousTrainingPipelineValidator().validate(invalid)
    }
}

@Test(.timeLimit(.minutes(1))) func autonomyPipelineExecutionAllowsPartialPendingStages() throws {
    let plan = AutonomousTrainingPipelineFactory().defaultPlan(domain: .aerialDrone, taskProfileIDs: ["lift-v1"])
    let report = AutonomousTrainingPipelineExecutionSynthesizer().makeReport(
        plan: plan,
        completions: [
            AutonomousTrainingStageCompletion(
                stageID: "imitation-bootstrap",
                satisfiedGates: [.modelBundleValidated, .artifactLineageComplete],
                evidence: [
                    AutonomousTrainingStageEvidence(
                        kind: .checkpointEvaluation,
                        path: "/tmp/checkpoint-evaluation.json",
                        safetyGate: .modelBundleValidated
                    ),
                    AutonomousTrainingStageEvidence(
                        kind: .checkpointEvaluation,
                        path: "/tmp/checkpoint-evaluation.json",
                        safetyGate: .artifactLineageComplete
                    )
                ]
            )
        ]
    )

    try AutonomousTrainingPipelineExecutionValidator().validate(report, plan: plan)
    #expect(report.stageRecords.filter { $0.status == .completed }.count == 1)
    #expect(report.stageRecords.filter { $0.status == .pending }.count == plan.stages.count - 1)
}

@Test(.timeLimit(.minutes(1))) func autonomyPipelineExecutionSynthesizerRecordsBlockedStages() throws {
    let plan = AutonomousTrainingPipelineFactory().defaultPlan(domain: .aerialDrone, taskProfileIDs: ["lift-v1"])
    let report = AutonomousTrainingPipelineExecutionSynthesizer().makeReport(
        plan: plan,
        completions: [],
        blocks: [
            AutonomousTrainingStageBlock(
                stageID: "evolution-search",
                failureReasons: ["no-accepted-evolution-checkpoint"],
                evidence: [
                    AutonomousTrainingStageEvidence(kind: .evolutionArtifact, path: "/tmp/evolution")
                ]
            )
        ]
    )

    try AutonomousTrainingPipelineExecutionValidator().validate(report, plan: plan)
    let blocked = try #require(report.stageRecords.first { $0.stageID == "evolution-search" })
    #expect(blocked.status == .blocked)
    #expect(blocked.failureReasons == ["no-accepted-evolution-checkpoint"])
}

@Test(.timeLimit(.minutes(1))) func autonomyPipelineExecutionSynthesizerKeepsFirstDuplicateCompletion() throws {
    let plan = AutonomousTrainingPipelineFactory().defaultPlan(domain: .aerialDrone, taskProfileIDs: ["lift-v1"])
    let report = AutonomousTrainingPipelineExecutionSynthesizer().makeReport(
        plan: plan,
        completions: [
            AutonomousTrainingStageCompletion(
                stageID: "imitation-bootstrap",
                satisfiedGates: [.modelBundleValidated, .artifactLineageComplete],
                evidence: [AutonomousTrainingStageEvidence(kind: .checkpointEvaluation, path: "/tmp/a")]
            ),
            AutonomousTrainingStageCompletion(
                stageID: "imitation-bootstrap",
                satisfiedGates: [],
                evidence: [AutonomousTrainingStageEvidence(kind: .checkpointEvaluation, path: "/tmp/b")]
            )
        ]
    )

    let record = try #require(report.stageRecords.first { $0.stageID == "imitation-bootstrap" })
    #expect(record.evidence.first?.path == "/tmp/a")
}

@Test(.timeLimit(.minutes(1))) func reinforcementStageCompletionComesFromAcceptedRLArtifact() throws {
    let plan = AutonomousTrainingPipelineFactory().defaultPlan(domain: .aerialDrone, taskProfileIDs: ["lift-v1"])
    let stage = try #require(plan.stages.first { $0.kind == .reinforcement })
    let artifactDirectory = URL(fileURLWithPath: "/tmp/rl-run", isDirectory: true)
    let checkpointURL = URL(fileURLWithPath: "/tmp/rl-run/checkpoints/accepted", isDirectory: true)
    let bundle = makeTrainingRunArtifactBundle(
        artifactDirectory: artifactDirectory,
        mode: .rlRollout,
        accepted: true,
        checkpointState: .accepted,
        checkpointURL: checkpointURL
    )

    let completion = try AutonomousTrainingStageCompletionFactory().reinforcementCompletion(
        stage: stage,
        bundle: bundle
    )

    #expect(completion.stageID == stage.stageID)
    #expect(completion.satisfiedGates == stage.requiredExitGates)
    #expect(completion.evidence.first?.kind == .trainingRunArtifact)
    #expect(completion.evidence.first?.path == artifactDirectory.path)
    #expect(completion.evidence.contains { $0.kind == .modelBundle && $0.path == checkpointURL.path })
    #expect(Set(completion.evidence.compactMap(\.safetyGate)).isSuperset(of: Set(stage.requiredExitGates)))
}

@Test(.timeLimit(.minutes(1))) func reinforcementStageCompletionRejectsSupervisedArtifact() throws {
    let plan = AutonomousTrainingPipelineFactory().defaultPlan(domain: .aerialDrone, taskProfileIDs: ["lift-v1"])
    let stage = try #require(plan.stages.first { $0.kind == .reinforcement })
    let bundle = makeTrainingRunArtifactBundle(
        mode: .supervised,
        accepted: true,
        checkpointState: .accepted,
        checkpointURL: URL(fileURLWithPath: "/tmp/checkpoint", isDirectory: true)
    )

    #expect(throws: AutonomousTrainingStageCompletionError.trainingRunModeMismatch(
        expected: [.rlRollout, .imaginationRL],
        actual: .supervised
    )) {
        try AutonomousTrainingStageCompletionFactory().reinforcementCompletion(
            stage: stage,
            bundle: bundle
        )
    }
}

@Test(.timeLimit(.minutes(1))) func reinforcementStageCompletionRejectsRejectedRLArtifact() throws {
    let plan = AutonomousTrainingPipelineFactory().defaultPlan(domain: .aerialDrone, taskProfileIDs: ["lift-v1"])
    let stage = try #require(plan.stages.first { $0.kind == .reinforcement })
    let bundle = makeTrainingRunArtifactBundle(
        mode: .rlRollout,
        accepted: false,
        checkpointState: .rejected,
        checkpointURL: URL(fileURLWithPath: "/tmp/checkpoint", isDirectory: true)
    )

    #expect(throws: AutonomousTrainingStageCompletionError.trainingRunNotAccepted(reason: "not-accepted")) {
        try AutonomousTrainingStageCompletionFactory().reinforcementCompletion(
            stage: stage,
            bundle: bundle
        )
    }
}

@Test(.timeLimit(.minutes(1))) func reinforcementStageCompletionRejectsMismatchedTaskProfile() throws {
    let plan = AutonomousTrainingPipelineFactory().defaultPlan(domain: .aerialDrone, taskProfileIDs: ["lift-v1"])
    let stage = try #require(plan.stages.first { $0.kind == .reinforcement })
    let bundle = makeTrainingRunArtifactBundle(
        mode: .rlRollout,
        suiteID: "singleLift-v1",
        accepted: true,
        checkpointState: .accepted,
        checkpointURL: URL(fileURLWithPath: "/tmp/checkpoint", isDirectory: true)
    )

    #expect(throws: AutonomousTrainingStageCompletionError.trainingRunProfileMismatch(
        expected: ["lift-v1"],
        actual: "singleLift-v1"
    )) {
        try AutonomousTrainingStageCompletionFactory().reinforcementCompletion(
            stage: stage,
            bundle: bundle
        )
    }
}

private func makeTrainingRunArtifactBundle(
    artifactDirectory: URL = URL(fileURLWithPath: "/tmp/training-run", isDirectory: true),
    mode: LearningRunMode,
    suiteID: String = "lift-v1",
    accepted: Bool,
    checkpointState: CheckpointDecisionState,
    checkpointURL: URL?
) -> TrainingRunArtifactBundle {
    let runID = "training-run-fixture"
    let manifest = LearningRunManifest(
        runID: runID,
        mode: mode,
        configHash: "config",
        suiteID: suiteID,
        seedSet: [1],
        policyID: "manasMLX",
        outputCheckpointID: checkpointURL?.lastPathComponent,
        workerCount: 1,
        startedAt: Date(timeIntervalSince1970: 1),
        completedAt: Date(timeIntervalSince1970: 2),
        terminalState: accepted ? .completed : .rejected,
        failureReason: accepted ? nil : "not-accepted"
    )
    let convergence = ConvergenceSummary(
        runID: runID,
        accepted: accepted,
        reason: accepted ? "accepted" : "not-accepted",
        bestCheckpointID: checkpointURL?.lastPathComponent,
        rewardMovingAverage: accepted ? 1 : -1,
        passRate: accepted ? 1 : 0,
        failureRate: accepted ? 0 : 1,
        safetyRegressionDetected: false,
        plateauDetected: false,
        overfitRiskDetected: false
    )
    let decision = CheckpointDecision(
        runID: runID,
        state: checkpointState,
        reason: checkpointState == .accepted ? "accepted" : "not-accepted",
        candidateCheckpointID: checkpointURL?.lastPathComponent,
        candidateCheckpointURL: checkpointURL,
        publishedCheckpointURL: checkpointState == .accepted ? checkpointURL : nil,
        decidedAt: Date(timeIntervalSince1970: 2)
    )
    return TrainingRunArtifactBundle(
        artifactDirectory: artifactDirectory,
        contract: TrainingRunArtifactContract(),
        manifest: manifest,
        metrics: [],
        convergence: convergence,
        checkpointDecision: decision
    )
}

@Test(.timeLimit(.minutes(1))) func autonomyPipelineExecutionRejectsCompletedStageWithoutGateEvidence() throws {
    let plan = AutonomousTrainingPipelineFactory().defaultPlan(domain: .aerialDrone, taskProfileIDs: ["lift-v1"])
    let records = plan.stages.map { stage in
        AutonomousTrainingStageExecutionRecord(
            stageID: stage.stageID,
            kind: stage.kind,
            status: stage.kind == .imitation ? .completed : .pending,
            satisfiedGates: stage.kind == .imitation ? [.modelBundleValidated, .artifactLineageComplete] : [],
            evidence: stage.kind == .imitation
                ? [
                    AutonomousTrainingStageEvidence(
                        kind: .checkpointEvaluation,
                        path: "/tmp/checkpoint-evaluation.json",
                        safetyGate: .modelBundleValidated
                    )
                ]
                : []
        )
    }
    let report = AutonomousTrainingPipelineExecutionReport(
        planID: plan.planID,
        domain: plan.domain,
        stageRecords: records,
        satisfiedTerminalGates: []
    )

    #expect(throws: AutonomousTrainingPipelineExecutionValidationError.completedStageMissingGateEvidence(
        stageID: "imitation-bootstrap",
        gate: .artifactLineageComplete
    )) {
        try AutonomousTrainingPipelineExecutionValidator().validate(report, plan: plan)
    }
}

@Test(.timeLimit(.minutes(1))) func autonomyPipelineExecutionRejectsCompletedStageWithoutExitGate() throws {
    let plan = AutonomousTrainingPipelineFactory().defaultPlan(domain: .aerialDrone, taskProfileIDs: ["lift-v1"])
    let records = plan.stages.map { stage in
        AutonomousTrainingStageExecutionRecord(
            stageID: stage.stageID,
            kind: stage.kind,
            status: stage.kind == .imitation ? .completed : .pending,
            satisfiedGates: [],
            evidence: stage.kind == .imitation
                ? [AutonomousTrainingStageEvidence(kind: .checkpointEvaluation, path: "/tmp/checkpoint-evaluation.json")]
                : []
        )
    }
    let report = AutonomousTrainingPipelineExecutionReport(
        planID: plan.planID,
        domain: plan.domain,
        stageRecords: records,
        satisfiedTerminalGates: []
    )

    #expect(throws: AutonomousTrainingPipelineExecutionValidationError.completedStageMissingExitGate(
        stageID: "imitation-bootstrap",
        gate: .modelBundleValidated
    )) {
        try AutonomousTrainingPipelineExecutionValidator().validate(report, plan: plan)
    }
}
