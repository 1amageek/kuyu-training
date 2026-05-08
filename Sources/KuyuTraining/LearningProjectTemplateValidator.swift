import Foundation

public struct LearningProjectTemplateValidator: Sendable {
    public let requiresKnownTaskProfile: Bool

    public init(requiresKnownTaskProfile: Bool = false) {
        self.requiresKnownTaskProfile = requiresKnownTaskProfile
    }

    public func validate(_ template: LearningProjectTemplate) throws {
        try validateIdentity(template)
        try validateDescriptor(template.descriptor)
        try validateTaskProfile(template)
        try validateObservation(template.observation)
        try validateAction(template.action)
        try validateCurriculum(template.curriculum)
        try validateEvaluationGate(template.evaluationGate)
        try validateCompute(template.compute)
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

    private func validateDescriptor(_ descriptor: LearningProjectDescriptorReference) throws {
        if descriptor.descriptorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LearningProjectTemplateValidationError.emptyDescriptorID
        }
        switch descriptor.source {
        case .filePath, .remote:
            if descriptor.path?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                throw LearningProjectTemplateValidationError.descriptorPathRequired(source: descriptor.source)
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
            if requiresKnownTaskProfile {
                throw LearningProjectTemplateValidationError.unsupportedTaskProfile(task: template.task)
            }
        }
    }

    private func validateObservation(_ observation: LearningProjectObservationContract) throws {
        if observation.schemaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LearningProjectTemplateValidationError.emptyObservationSchemaID
        }
        if observation.channelCount <= 0 {
            throw LearningProjectTemplateValidationError.invalidObservationChannelCount(
                expected: 1,
                actual: observation.channelCount
            )
        }
        if observation.channels.count != observation.channelCount {
            throw LearningProjectTemplateValidationError.observationChannelCountMismatch(
                expected: observation.channelCount,
                actual: observation.channels.count
            )
        }
        var seen: Set<Int> = []
        for channel in observation.channels {
            if channel.index < 0 || channel.index >= observation.channelCount {
                throw LearningProjectTemplateValidationError.invalidObservationChannelCount(
                    expected: observation.channelCount,
                    actual: channel.index
                )
            }
            if seen.contains(channel.index) {
                throw LearningProjectTemplateValidationError.duplicateObservationChannel(index: channel.index)
            }
            seen.insert(channel.index)
        }
    }

    private func validateAction(_ action: LearningProjectActionContract) throws {
        if action.schemaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LearningProjectTemplateValidationError.invalidActionContract(reason: "empty-schema-id")
        }
        if let driveCount = action.driveCount, driveCount <= 0 {
            throw LearningProjectTemplateValidationError.invalidActionContract(reason: "non-positive-drive-count")
        }
        if let actuatorCount = action.actuatorCount, actuatorCount <= 0 {
            throw LearningProjectTemplateValidationError.invalidActionContract(reason: "non-positive-actuator-count")
        }
        if action.driveCount == nil && action.actuatorCount == nil {
            throw LearningProjectTemplateValidationError.invalidActionContract(reason: "missing-drive-or-actuator-count")
        }
    }

    private func validateCurriculum(_ curriculum: LearningProjectCurriculum) throws {
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
        if curriculum.eliteCount < 0 || curriculum.eliteCount > curriculum.populationSize {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "invalid-elite-count")
        }
        if let maxStepCount = curriculum.maxStepCount, maxStepCount <= 0 {
            throw LearningProjectTemplateValidationError.invalidCurriculum(reason: "non-positive-max-step-count")
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
        if let estimatedDiskBytes = compute.estimatedDiskBytes, estimatedDiskBytes < 0 {
            throw LearningProjectTemplateValidationError.invalidComputeProfile(reason: "negative-estimated-disk-bytes")
        }
    }
}
