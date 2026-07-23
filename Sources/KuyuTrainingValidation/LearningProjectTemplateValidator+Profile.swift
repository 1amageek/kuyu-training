import KuyuTrainingContracts

extension LearningProjectTemplateValidator {
    func validateTaskProfile(_ template: LearningProjectTemplate) throws {
        do {
            let profile = try TaskEvaluationProfile.profile(task: template.task)
            try validateTaskProfileContract(profile, robotClass: template.robotManifest.robotClass)
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

    func validateTaskProfileContract(
        _ profile: TaskEvaluationProfile,
        robotClass: LearningProjectRobotClass
    ) throws {
        do {
            try TaskEvaluationProfileContractValidator().validate(profile, robotClass: robotClass)
        } catch TaskEvaluationProfileContractValidationError.invalidProfile(let profileID, let reason) {
            throw LearningProjectTemplateValidationError.invalidTaskProfileContract(
                profileID: profileID,
                reason: reason
            )
        }
    }

    func validateProfileOwnedPolicySemantics(_ template: LearningProjectTemplate) throws {
        guard template.policy.actionEncoding == .ctbr else { return }
        guard let profile = try effectiveProfileOwner(for: template),
              profile.family == .referenceQuadrotor else {
            throw LearningProjectTemplateValidationError.invalidPolicyContract(
                reason: "ctbr-requires-reference-quadrotor-profile"
            )
        }
    }

    func effectiveProfileOwner(for template: LearningProjectTemplate) throws -> TaskEvaluationProfile? {
        if let taskProfileID = template.taskProfileID {
            return try TaskEvaluationProfile.profile(profileID: taskProfileID)
        }
        if let runnableStage = template.primaryRunnableTrainingStage,
           let taskProfileID = runnableStage.taskProfileID {
            return try TaskEvaluationProfile.profile(profileID: taskProfileID)
        }
        return nil
    }
}
