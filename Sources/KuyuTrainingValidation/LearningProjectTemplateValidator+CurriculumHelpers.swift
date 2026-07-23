import KuyuTrainingContracts

extension LearningProjectTemplateValidator {
    func validateStageGoal(_ stage: LearningProjectTrainingStage) throws {
        if stage.kind == .regression && stage.convergenceGoal.kind != .validationGate {
            throw LearningProjectTemplateValidationError.invalidCurriculum(
                reason: "regression-stage-without-validation-gate"
            )
        }
        if stage.kind == .regression && stage.generationLimit != 1 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(
                reason: "regression-stage-must-be-single-pass"
            )
        }
        if stage.convergenceGoal.kind == .convergence,
           stage.generationLimit < stage.convergenceGoal.patienceGenerations {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "stage-generation-budget-below-patience")
        }
    }

    func validateStageTaskProfile(
        _ stage: LearningProjectTrainingStage,
        robotManifest: LearningProjectRobotManifestReference
    ) throws {
        guard let taskProfileID = stage.taskProfileID else { return }
        do {
            let profile = try TaskEvaluationProfile.profile(task: stage.task)
            try validateTaskProfileContract(profile, robotClass: robotManifest.robotClass)
            if taskProfileID != profile.profileID {
                throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "stage-task-profile-mismatch")
            }
        } catch TaskEvaluationProfileError.unsupportedTask {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "stage-task-profile-unsupported")
        }
    }

    func validateStageDependencies(
        _ stages: [LearningProjectTrainingStage],
        stageIDs: Set<String>
    ) throws {
        for stage in stages {
            for dependency in stage.dependsOnStageIDs {
                if dependency == stage.stageID {
                    throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "stage-depends-on-self")
                }
                if !stageIDs.contains(dependency) {
                    throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "unknown-stage-dependency")
                }
            }
        }
    }

    func validateStageKindOrder(_ stages: [LearningProjectTrainingStage]) throws {
        let firstByKind = Dictionary(
            stages.enumerated().map { ($0.element.kind, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )

        try requireStageKind(
            .reinforcement,
            before: .evolution,
            firstByKind: firstByKind,
            reason: "reinforcement-must-precede-evolution"
        )
        try requireStageKind(
            .evolution,
            before: .stress,
            firstByKind: firstByKind,
            reason: "evolution-must-precede-stress"
        )
        try requireStageKind(
            .stress,
            before: .regression,
            firstByKind: firstByKind,
            reason: "stress-must-precede-regression"
        )
        try requireStageKind(
            .evolution,
            before: .regression,
            firstByKind: firstByKind,
            reason: "evolution-must-precede-regression"
        )
    }

    func requireStageKind(
        _ requiredBefore: AutonomousTrainingStageKind,
        before requiredAfter: AutonomousTrainingStageKind,
        firstByKind: [AutonomousTrainingStageKind: Int],
        reason: String
    ) throws {
        guard let beforeIndex = firstByKind[requiredBefore],
              let afterIndex = firstByKind[requiredAfter] else {
            return
        }
        if beforeIndex >= afterIndex {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: reason)
        }
    }
}
