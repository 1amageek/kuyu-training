import KuyuTrainingContracts

public struct EvolutionCandidateAcceptanceEvaluationContract: Sendable, Codable, Equatable {
    public let evaluatorID: String
    public let scenarioSuiteIDs: [String]
    public let episodesPerSuite: Int
    public let determinismTier: String
    public let configurationDigest: String
    public let robotManifestID: String?
    public let robotManifestHash: String?
    public let evaluationFidelity: TrainingEvaluationFidelity
    public let workPhase: TrainingWorkPhase
    public let worldExecutionRequirement: VectorizedWorldExecutionRequirement

    public init(
        evaluatorID: String,
        scenarioSuiteIDs: [String],
        episodesPerSuite: Int,
        determinismTier: String,
        configurationDigest: String,
        robotManifestID: String? = nil,
        robotManifestHash: String? = nil,
        evaluationFidelity: TrainingEvaluationFidelity,
        workPhase: TrainingWorkPhase,
        worldExecutionRequirement: VectorizedWorldExecutionRequirement
    ) {
        self.evaluatorID = evaluatorID
        self.scenarioSuiteIDs = scenarioSuiteIDs
        self.episodesPerSuite = episodesPerSuite
        self.determinismTier = determinismTier
        self.configurationDigest = configurationDigest
        self.robotManifestID = robotManifestID
        self.robotManifestHash = robotManifestHash
        self.evaluationFidelity = evaluationFidelity
        self.workPhase = workPhase
        self.worldExecutionRequirement = worldExecutionRequirement
    }
}
