import Foundation
import KuyuTrainingContracts

extension LearningProjectTemplateValidator {
    func validateCurriculum(
        _ curriculum: LearningProjectCurriculum,
        strategy: LearningProjectTrainingStrategy,
        robotManifest: LearningProjectRobotManifestReference
    ) throws {
        if curriculum.suiteIDs.isEmpty {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "empty-suite-ids")
        }
        if curriculum.seedCount <= 0 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "non-positive-seed-count")
        }
        if curriculum.episodesPerSuite <= 0 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "non-positive-episodes")
        }
        if curriculum.populationSize <= 0 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "non-positive-population")
        }
        if curriculum.generationLimit <= 0 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "non-positive-generation-limit")
        }
        try validateConvergenceGoal(curriculum.convergenceGoal, context: "curriculum")
        if curriculum.convergenceGoal.kind == .convergence,
           curriculum.generationLimit < curriculum.convergenceGoal.patienceGenerations {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "generation-budget-below-patience")
        }
        if curriculum.eliteCount < 0 || curriculum.eliteCount > curriculum.populationSize {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "invalid-elite-count")
        }
        if let maxStepCount = curriculum.maxStepCount, maxStepCount <= 0 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "non-positive-max-step-count")
        }
        if curriculum.trainingStages.isEmpty {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "empty-training-stages")
        }
        try validateStrategyStageCoverage(curriculum, strategy: strategy)
        try validateStageKindOrder(curriculum.trainingStages)
        try validateTrainingStages(curriculum.trainingStages, robotManifest: robotManifest)
    }

    func validateStrategyStageCoverage(
        _ curriculum: LearningProjectCurriculum,
        strategy: LearningProjectTrainingStrategy
    ) throws {
        let stageKinds = Set(curriculum.trainingStages.map(\.kind))
        if strategy.usesReinforcementFineTuning && !stageKinds.contains(.reinforcement) {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "missing-reinforcement-stage")
        }
        if strategy.kind == .hybrid && !stageKinds.contains(.evolution) {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "missing-evolution-stage")
        }
        if strategy.usesQualityGate && !stageKinds.contains(.regression) {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "missing-regression-stage")
        }
    }

    func validateTrainingStages(
        _ stages: [LearningProjectTrainingStage],
        robotManifest: LearningProjectRobotManifestReference
    ) throws {
        var stageIDs: Set<String> = []
        for stage in stages {
            try validateTrainingStage(stage, robotManifest: robotManifest)
            if stageIDs.contains(stage.stageID) {
                throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "duplicate-stage-id")
            }
            stageIDs.insert(stage.stageID)
        }
        try validateStageDependencies(stages, stageIDs: stageIDs)
    }

    func validateTrainingStage(
        _ stage: LearningProjectTrainingStage,
        robotManifest: LearningProjectRobotManifestReference
    ) throws {
        if stage.stageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "empty-stage-id")
        }
        if stage.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "empty-stage-display-name")
        }
        if stage.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "empty-stage-task")
        }
        if stage.suiteIDs.isEmpty {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "empty-stage-suite-ids")
        }
        if stage.seedCount <= 0 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "non-positive-stage-seed-count")
        }
        if stage.episodesPerSuite <= 0 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "non-positive-stage-episodes")
        }
        if stage.generationLimit <= 0 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "non-positive-stage-generation-limit")
        }
        try validateConvergenceGoal(stage.convergenceGoal, context: "stage-\(stage.stageID)")
        try validateStageGoal(stage)
        try validateStageTaskProfile(stage, robotManifest: robotManifest)
    }
}
