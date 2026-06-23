import Foundation

public enum LearningProjectTemplateExecutionLevel: String, Codable, Sendable, Equatable, CaseIterable {
    case runnableStarter
    case requiresExistingModel
    case designOnly

    public var displayName: String {
        switch self {
        case .runnableStarter:
            return "Ready Now"
        case .requiresExistingModel:
            return "Requires Model"
        case .designOnly:
            return "Design Only"
        }
    }
}

public struct LearningProjectTemplate: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let templateID: String
    public let displayName: String
    public let summary: String
    public let domain: AutonomousOperationDomain
    public let task: String
    public let taskProfileID: String?
    public let robotManifest: LearningProjectRobotManifestReference
    public let modelBundlePolicy: LearningProjectModelBundlePolicy
    public let trainingStrategy: LearningProjectTrainingStrategy
    public let curriculum: LearningProjectCurriculum
    public let evaluationGate: LearningProjectEvaluationGate
    public let observation: LearningProjectObservationContract
    public let action: LearningProjectActionContract
    public let policy: LearningProjectPolicyContract
    public let compute: LearningProjectComputeProfile
    public let tags: [String]

    public var executionLevel: LearningProjectTemplateExecutionLevel {
        switch modelBundlePolicy.sourceCheckpointPolicy {
        case .createStarter:
            return primaryRunnableTrainingStage == nil ? .designOnly : .runnableStarter
        case .requireExisting, .optionalExisting:
            return primaryRunnableTrainingStage == nil ? .designOnly : .requiresExistingModel
        case .none:
            return .designOnly
        }
    }

    public var isRunnableStarter: Bool {
        executionLevel == .runnableStarter
    }

    public var primaryRunnableTrainingStage: LearningProjectTrainingStage? {
        do {
            return try LearningProjectCurriculumStageResolver()
                .nextRunnableStage(in: curriculum, completedStageIDs: [])
        } catch {
            return nil
        }
    }

    public init(
        schemaVersion: Int = LearningProjectTemplate.currentSchemaVersion,
        templateID: String,
        displayName: String,
        summary: String,
        domain: AutonomousOperationDomain,
        task: String,
        taskProfileID: String?,
        robotManifest: LearningProjectRobotManifestReference,
        modelBundlePolicy: LearningProjectModelBundlePolicy,
        trainingStrategy: LearningProjectTrainingStrategy,
        curriculum: LearningProjectCurriculum,
        evaluationGate: LearningProjectEvaluationGate,
        observation: LearningProjectObservationContract,
        action: LearningProjectActionContract,
        policy: LearningProjectPolicyContract,
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
        self.robotManifest = robotManifest
        self.modelBundlePolicy = modelBundlePolicy
        self.trainingStrategy = trainingStrategy
        self.curriculum = curriculum
        self.evaluationGate = evaluationGate
        self.observation = observation
        self.action = action
        self.policy = policy
        self.compute = compute
        self.tags = tags
    }
}
