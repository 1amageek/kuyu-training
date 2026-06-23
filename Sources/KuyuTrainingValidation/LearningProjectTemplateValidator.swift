import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public struct LearningProjectTemplateValidator: Sendable {
    public let requiresKnownTaskProfile: Bool

    public init(requiresKnownTaskProfile: Bool = false) {
        self.requiresKnownTaskProfile = requiresKnownTaskProfile
    }

    public func validate(_ template: LearningProjectTemplate) throws {
        try validateIdentity(template)
        try validateRobotManifest(template.robotManifest)
        try validateTaskProfile(template)
        try validateObservation(template.observation)
        try validateAction(template.action)
        try validatePolicy(template.policy, observation: template.observation, action: template.action)
        try validateCurriculum(template.curriculum, strategy: template.trainingStrategy)
        try validateEvaluationGate(template.evaluationGate)
        try validateCompute(template.compute)
        try validateTemplateConsistency(template)
    }

    private func validateIdentity(_ template: LearningProjectTemplate) throws {
        if template.schemaVersion != LearningProjectTemplate.currentSchemaVersion {
            throw LearningProjectTemplateValidationError.unsupportedSchemaVersion(
                expected: LearningProjectTemplate.currentSchemaVersion,
                actual: template.schemaVersion
            )
        }
        if template.templateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LearningProjectTemplateValidationError.emptyTemplateID
        }
        if template.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LearningProjectTemplateValidationError.emptyDisplayName
        }
        if template.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LearningProjectTemplateValidationError.emptyTask
        }
    }

    private func validateRobotManifest(_ robotManifest: LearningProjectRobotManifestReference) throws {
        if robotManifest.robotManifestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LearningProjectTemplateValidationError.emptyRobotManifestID
        }
        switch robotManifest.source {
        case .filePath, .remote:
            if robotManifest.path?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                throw LearningProjectTemplateValidationError.robotManifestPathRequired(source: robotManifest.source)
            }
        case .bundled, .generated:
            break
        }
    }

    private func validateTaskProfile(_ template: LearningProjectTemplate) throws {
        do {
            let profile = try TaskEvaluationProfile.profile(task: template.task)
            if template.taskProfileID != profile.profileID {
                throw LearningProjectTemplateValidationError.invalidTaskProfile(
                    expected: profile.profileID,
                    actual: template.taskProfileID
                )
            }
            if template.observation.channelCount != profile.observationChannelCount {
                throw LearningProjectTemplateValidationError.invalidObservationChannelCount(
                    expected: profile.observationChannelCount,
                    actual: template.observation.channelCount
                )
            }
        } catch TaskEvaluationProfileError.unsupportedTask {
            if requiresKnownTaskProfile && template.primaryRunnableTrainingStage == nil {
                throw LearningProjectTemplateValidationError.unsupportedTaskProfile(task: template.task)
            }
        }
    }

    private func validateObservation(_ observation: LearningProjectObservationContract) throws {
        do {
            try LearningProjectContractValidator().validateObservation(observation)
        } catch LearningProjectContractValidationError.invalidObservation(let reason) {
            switch reason {
            case "empty-schema-id":
                throw LearningProjectTemplateValidationError.emptyObservationSchemaID
            case "non-positive-channel-count":
                throw LearningProjectTemplateValidationError.invalidObservationChannelCount(
                    expected: 1,
                    actual: observation.channelCount
                )
            case "channel-count-mismatch":
                throw LearningProjectTemplateValidationError.observationChannelCountMismatch(
                    expected: observation.channelCount,
                    actual: observation.channels.count
                )
            case "channel-index-out-of-range":
                let invalidIndex = observation.channels.first { channel in
                    channel.index < 0 || channel.index >= observation.channelCount
                }?.index ?? -1
                throw LearningProjectTemplateValidationError.invalidObservationChannelCount(
                    expected: observation.channelCount,
                    actual: invalidIndex
                )
            case "duplicate-channel-index":
                var seen: Set<Int> = []
                let duplicate = observation.channels.first { channel in
                    if seen.contains(channel.index) {
                        return true
                    }
                    seen.insert(channel.index)
                    return false
                }?.index ?? -1
                throw LearningProjectTemplateValidationError.duplicateObservationChannel(index: duplicate)
            default:
                throw LearningProjectTemplateValidationError.invalidObservationContract(reason: reason)
            }
        } catch {
            throw error
        }
    }

    private func validateAction(_ action: LearningProjectActionContract) throws {
        do {
            try LearningProjectContractValidator().validateAction(action)
        } catch LearningProjectContractValidationError.invalidAction(let reason) {
            throw LearningProjectTemplateValidationError.invalidActionContract(reason: reason)
        } catch {
            throw error
        }
    }

    private func validatePolicy(
        _ policy: LearningProjectPolicyContract,
        observation: LearningProjectObservationContract,
        action: LearningProjectActionContract
    ) throws {
        do {
            try LearningProjectContractValidator().validatePolicy(
                policy,
                observation: observation,
                action: action
            )
        } catch LearningProjectContractValidationError.invalidPolicy(let reason) {
            throw LearningProjectTemplateValidationError.invalidPolicyContract(reason: reason)
        } catch {
            throw error
        }
    }

    private func validateCurriculum(
        _ curriculum: LearningProjectCurriculum,
        strategy: LearningProjectTrainingStrategy
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
        let stageKinds = Set(curriculum.trainingStages.map(\.kind))
        if strategy.usesReinforcementFineTuning && !stageKinds.contains(.reinforcement) {
            throw LearningProjectTemplateValidationError.invalidCurriculum(
                reason: "missing-reinforcement-stage"
            )
        }
        if strategy.kind == .hybrid && !stageKinds.contains(.evolution) {
            throw LearningProjectTemplateValidationError.invalidCurriculum(
                reason: "missing-evolution-stage"
            )
        }
        if strategy.usesQualityGate && !stageKinds.contains(.regression) {
            throw LearningProjectTemplateValidationError.invalidCurriculum(
                reason: "missing-regression-stage"
            )
        }
        try validateStageKindOrder(curriculum.trainingStages)
        var stageIDs: Set<String> = []
        for stage in curriculum.trainingStages {
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
            if let taskProfileID = stage.taskProfileID {
                do {
                    let profile = try TaskEvaluationProfile.profile(task: stage.task)
                    if taskProfileID != profile.profileID {
                        throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "stage-task-profile-mismatch")
                    }
                } catch TaskEvaluationProfileError.unsupportedTask {
                    throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "stage-task-profile-unsupported")
                }
            }
            if stageIDs.contains(stage.stageID) {
                throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "duplicate-stage-id")
            }
            stageIDs.insert(stage.stageID)
        }
        for stage in curriculum.trainingStages {
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

    private func validateStageKindOrder(_ stages: [LearningProjectTrainingStage]) throws {
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

    private func requireStageKind(
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

    private func validateConvergenceGoal(
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

    private func validateEvaluationGate(_ gate: LearningProjectEvaluationGate) throws {
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

    private func validateCompute(_ compute: LearningProjectComputeProfile) throws {
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

    private func validateTemplateConsistency(_ template: LearningProjectTemplate) throws {
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
