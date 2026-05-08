import Foundation

public struct KuyuProjectExperiment: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let experimentID: String
    public let templateID: String
    public let name: String
    public let summary: String
    public let task: String
    public let domain: AutonomousOperationDomain
    public let tags: [String]
    public let curriculum: LearningProjectCurriculum
    public let trainingStrategy: LearningProjectTrainingStrategy
    public let evaluationGate: LearningProjectEvaluationGate
    public let observation: LearningProjectObservationContract
    public let action: LearningProjectActionContract
    public let compute: LearningProjectComputeProfile
    public let createdAt: Date

    public init(
        schemaVersion: Int = KuyuProjectExperiment.currentSchemaVersion,
        experimentID: String,
        templateID: String,
        name: String,
        summary: String,
        task: String,
        domain: AutonomousOperationDomain,
        tags: [String],
        curriculum: LearningProjectCurriculum,
        trainingStrategy: LearningProjectTrainingStrategy,
        evaluationGate: LearningProjectEvaluationGate,
        observation: LearningProjectObservationContract,
        action: LearningProjectActionContract,
        compute: LearningProjectComputeProfile,
        createdAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.experimentID = experimentID
        self.templateID = templateID
        self.name = name
        self.summary = summary
        self.task = task
        self.domain = domain
        self.tags = tags
        self.curriculum = curriculum
        self.trainingStrategy = trainingStrategy
        self.evaluationGate = evaluationGate
        self.observation = observation
        self.action = action
        self.compute = compute
        self.createdAt = createdAt
    }
}
