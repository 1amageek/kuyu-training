import Foundation

public struct TrainingRunRequest: Sendable, Equatable {
    public let runID: TrainingRunID
    public let projectRoot: URL?
    public let artifactRoot: URL
    public let taskProfileID: String
    public let policyContract: LearningProjectPolicyContract
    public let actionContract: LearningProjectActionContract
    public let sourceBundle: ModelBundleReference?
    public let seedCount: Int
    public let populationSize: Int
    public let generationLimit: Int?
    public let configuration: TrainingRunConfiguration

    public init(
        runID: TrainingRunID,
        projectRoot: URL? = nil,
        artifactRoot: URL,
        taskProfileID: String,
        policyContract: LearningProjectPolicyContract,
        actionContract: LearningProjectActionContract,
        sourceBundle: ModelBundleReference? = nil,
        seedCount: Int = 1,
        populationSize: Int = 1,
        generationLimit: Int? = nil,
        configuration: TrainingRunConfiguration = TrainingRunConfiguration()
    ) {
        self.runID = runID
        self.projectRoot = projectRoot
        self.artifactRoot = artifactRoot
        self.taskProfileID = taskProfileID
        self.policyContract = policyContract
        self.actionContract = actionContract
        self.sourceBundle = sourceBundle
        self.seedCount = max(1, seedCount)
        self.populationSize = max(1, populationSize)
        self.generationLimit = generationLimit.map { max(1, $0) }
        self.configuration = configuration
    }
}
