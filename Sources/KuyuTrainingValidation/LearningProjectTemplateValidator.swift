import KuyuTrainingContracts

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
        try validateProfileOwnedPolicySemantics(template)
        try validateCurriculum(
            template.curriculum,
            strategy: template.trainingStrategy,
            robotManifest: template.robotManifest
        )
        try validateEvaluationGate(template.evaluationGate)
        try validateCompute(template.compute)
        try validateTemplateConsistency(template)
    }
}
