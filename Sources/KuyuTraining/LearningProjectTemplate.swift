import Foundation

public struct LearningProjectTemplate: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let templateID: String
    public let displayName: String
    public let summary: String
    public let domain: AutonomousOperationDomain
    public let task: String
    public let taskProfileID: String?
    public let descriptor: LearningProjectDescriptorReference
    public let modelBundlePolicy: LearningProjectModelBundlePolicy
    public let trainingStrategy: LearningProjectTrainingStrategy
    public let curriculum: LearningProjectCurriculum
    public let evaluationGate: LearningProjectEvaluationGate
    public let observation: LearningProjectObservationContract
    public let action: LearningProjectActionContract
    public let compute: LearningProjectComputeProfile
    public let tags: [String]

    public init(
        schemaVersion: Int = LearningProjectTemplate.currentSchemaVersion,
        templateID: String,
        displayName: String,
        summary: String,
        domain: AutonomousOperationDomain,
        task: String,
        taskProfileID: String?,
        descriptor: LearningProjectDescriptorReference,
        modelBundlePolicy: LearningProjectModelBundlePolicy,
        trainingStrategy: LearningProjectTrainingStrategy,
        curriculum: LearningProjectCurriculum,
        evaluationGate: LearningProjectEvaluationGate,
        observation: LearningProjectObservationContract,
        action: LearningProjectActionContract,
        compute: LearningProjectComputeProfile,
        tags: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.templateID = templateID
        self.displayName = displayName
        self.summary = summary
        self.domain = domain
        self.task = task
        self.taskProfileID = taskProfileID
        self.descriptor = descriptor
        self.modelBundlePolicy = modelBundlePolicy
        self.trainingStrategy = trainingStrategy
        self.curriculum = curriculum
        self.evaluationGate = evaluationGate
        self.observation = observation
        self.action = action
        self.compute = compute
        self.tags = tags
    }
}
