import KuyuTrainingContracts

extension LearningProjectTemplateValidator {
    func validateCompute(_ compute: LearningProjectComputeProfile) throws {
        if compute.workerCount <= 0 {
            throw LearningProjectTemplateValidationError.invalidComputeProfile(reason: "non-positive-worker-count")
        }
        if compute.candidateEvaluationConcurrency <= 0 {
            throw LearningProjectTemplateValidationError.invalidComputeProfile(reason: "non-positive-candidate-concurrency")
        }
        if compute.minimumPopulationSize <= 0 {
            throw LearningProjectTemplateValidationError.invalidComputeProfile(reason: "non-positive-minimum-population")
        }
        if compute.candidateEvaluationConcurrency > compute.minimumPopulationSize {
            throw LearningProjectTemplateValidationError.invalidComputeProfile(reason: "candidate-concurrency-above-minimum-population")
        }
        if compute.requiresMetal, compute.targetAccelerator != .metal {
            throw LearningProjectTemplateValidationError.invalidComputeProfile(reason: "metal-required-without-metal-target")
        }
        if let estimatedDiskBytes = compute.estimatedDiskBytes, estimatedDiskBytes < 0 {
            throw LearningProjectTemplateValidationError.invalidComputeProfile(reason: "negative-estimated-disk-bytes")
        }
    }

    func validateTemplateConsistency(_ template: LearningProjectTemplate) throws {
        if template.curriculum.populationSize < template.compute.minimumPopulationSize {
            throw LearningProjectTemplateValidationError.invalidComputeProfile(reason: "population-below-compute-minimum")
        }
        if template.compute.candidateEvaluationConcurrency > template.curriculum.populationSize {
            throw LearningProjectTemplateValidationError.invalidComputeProfile(reason: "candidate-concurrency-above-population")
        }
        if template.curriculum.convergenceGoal.kind == .convergence,
           template.curriculum.generationLimit != template.curriculum.convergenceGoal.maxGenerationBudget {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "generation-limit-mismatch-convergence-budget")
        }
        for stage in template.curriculum.trainingStages where stage.convergenceGoal.kind == .convergence {
            if stage.generationLimit != stage.convergenceGoal.maxGenerationBudget {
                throw LearningProjectTemplateValidationError.invalidCurriculum(
                    reason: "stage-generation-limit-mismatch-convergence-budget"
                )
            }
        }
        let primaryRunnableStage = template.primaryRunnableTrainingStage
        if template.modelBundlePolicy.sourceCheckpointPolicy == .createStarter {
            guard primaryRunnableStage != nil else {
                throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "starter-missing-runnable-stage")
            }
        }
        if primaryRunnableStage == nil,
           template.modelBundlePolicy.sourceCheckpointPolicy != .none {
            throw LearningProjectTemplateValidationError.invalidCurriculum(
                reason: "non-runnable-template-must-not-request-model-bundle"
            )
        }
        if template.isRunnableStarter {
            guard template.compute.requiresMetal,
                  template.compute.targetAccelerator == .metal,
                  template.compute.usesMachineOptimizedParallelism else {
                throw LearningProjectTemplateValidationError.invalidComputeProfile(
                    reason: "runnable-starter-requires-machine-optimized-metal"
                )
            }
        }
    }
}
