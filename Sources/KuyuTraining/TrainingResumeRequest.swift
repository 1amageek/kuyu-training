import Foundation

public enum TrainingResumeSource: Sendable, Equatable {
    case artifactRoot(URL)
    case checkpoint(ModelBundleReference)
}

public struct TrainingResumeRequest: Sendable, Equatable {
    public let runID: TrainingRunID
    public let source: TrainingResumeSource
    public let destinationArtifactRoot: URL
    public let projectRoot: URL?
    public let taskProfileID: String
    public let policyContract: LearningProjectPolicyContract
    public let actionContract: LearningProjectActionContract
    public let seedCount: Int
    public let populationSize: Int
    public let generationLimit: Int?
    public let configuration: TrainingRunConfiguration

    public init(
        runID: TrainingRunID,
        source: TrainingResumeSource,
        destinationArtifactRoot: URL,
        projectRoot: URL? = nil,
        taskProfileID: String = "lift",
        policyContract: LearningProjectPolicyContract,
        actionContract: LearningProjectActionContract,
        seedCount: Int = 1,
        populationSize: Int = 1,
        generationLimit: Int? = nil,
        configuration: TrainingRunConfiguration = TrainingRunConfiguration()
    ) {
        self.runID = runID
        self.source = source
        self.destinationArtifactRoot = destinationArtifactRoot
        self.projectRoot = projectRoot
        self.taskProfileID = taskProfileID
        self.policyContract = policyContract
        self.actionContract = actionContract
        self.seedCount = max(1, seedCount)
        self.populationSize = max(1, populationSize)
        self.generationLimit = generationLimit.map { max(1, $0) }
        self.configuration = configuration
    }
}
