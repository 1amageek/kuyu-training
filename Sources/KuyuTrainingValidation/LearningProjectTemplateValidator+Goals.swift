import KuyuTrainingContracts

extension LearningProjectTemplateValidator {
    func validateConvergenceGoal(
        _ goal: LearningProjectConvergenceGoal,
        context: String
    ) throws {
        if !goal.targetTaskPassRate.isFinite || goal.targetTaskPassRate < 0 || goal.targetTaskPassRate > 1 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "\(context)-invalid-target-task-pass-rate")
        }
        if let hold = goal.targetHoldTimeRatio, !hold.isFinite || hold < 0 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "\(context)-invalid-target-hold-time-ratio")
        }
        if !goal.maximumSafetyViolationRate.isFinite || goal.maximumSafetyViolationRate < 0 || goal.maximumSafetyViolationRate > 1 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "\(context)-invalid-maximum-safety-violation-rate")
        }
        if !goal.minimumFitnessImprovement.isFinite || goal.minimumFitnessImprovement < 0 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "\(context)-invalid-minimum-fitness-improvement")
        }
        if !goal.minimumTaskPassRateImprovement.isFinite || goal.minimumTaskPassRateImprovement < 0 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "\(context)-invalid-minimum-task-pass-rate-improvement")
        }
        if !goal.minimumHoldTimeRatioImprovement.isFinite || goal.minimumHoldTimeRatioImprovement < 0 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "\(context)-invalid-minimum-hold-time-ratio-improvement")
        }
        if goal.patienceGenerations <= 0 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "\(context)-non-positive-patience")
        }
        if goal.maxGenerationBudget <= 0 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "\(context)-non-positive-generation-budget")
        }
    }

    func validateEvaluationGate(_ gate: LearningProjectEvaluationGate) throws {
        if let reward = gate.minimumRewardAverage, !reward.isFinite {
            throw LearningProjectTemplateValidationError.invalidEvaluationGate(reason: "non-finite-minimum-reward")
        }
        if !gate.minimumTaskPassRate.isFinite || gate.minimumTaskPassRate < 0 || gate.minimumTaskPassRate > 1 {
            throw LearningProjectTemplateValidationError.invalidEvaluationGate(reason: "invalid-task-pass-rate")
        }
        if let hold = gate.minimumHoldTimeRatio, !hold.isFinite || hold < 0 {
            throw LearningProjectTemplateValidationError.invalidEvaluationGate(reason: "invalid-hold-time-ratio")
        }
        if let altitude = gate.maximumAltitudeErrorRatio, !altitude.isFinite || altitude < 0 {
            throw LearningProjectTemplateValidationError.invalidEvaluationGate(reason: "invalid-altitude-error-ratio")
        }
    }
}
