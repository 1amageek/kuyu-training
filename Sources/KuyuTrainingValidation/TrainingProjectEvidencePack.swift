import Foundation

public struct TrainingProjectEvidencePack: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 2
    public static let fileName = "training-project-evidence-pack.json"

    public typealias DatasetLineageRecord = TrainingProjectDatasetLineageRecord
    public typealias CurriculumStageEvidence = TrainingProjectCurriculumStageEvidence
    public typealias CheckpointEvidence = TrainingProjectCheckpointEvidence
    public typealias RegressionArtifactReference = TrainingProjectRegressionArtifactReference
    public typealias StressCoverageTargetEvidence = TrainingProjectStressCoverageTargetEvidence
    public typealias StressSuiteEvidence = TrainingProjectStressSuiteEvidence
    public typealias PhysicsCorpusEvidence = TrainingProjectPhysicsCorpusEvidence
    public typealias ObservabilityArtifactEvidence = TrainingProjectObservabilityArtifactEvidence

    public let schemaVersion: Int
    public let projectID: String
    public let createdAt: Date
    public let datasets: [DatasetLineageRecord]
    public let curriculumStages: [CurriculumStageEvidence]
    public let checkpoint: CheckpointEvidence
    public let regressionArtifacts: [RegressionArtifactReference]
    public let stressSuites: [StressSuiteEvidence]
    public let physicsCorpora: [PhysicsCorpusEvidence]
    public let observabilityArtifacts: [ObservabilityArtifactEvidence]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        projectID: String,
        createdAt: Date = Date(),
        datasets: [DatasetLineageRecord],
        curriculumStages: [CurriculumStageEvidence],
        checkpoint: CheckpointEvidence,
        regressionArtifacts: [RegressionArtifactReference],
        stressSuites: [StressSuiteEvidence] = [],
        physicsCorpora: [PhysicsCorpusEvidence] = [],
        observabilityArtifacts: [ObservabilityArtifactEvidence] = []
    ) {
        self.schemaVersion = schemaVersion
        self.projectID = projectID
        self.createdAt = createdAt
        self.datasets = datasets
        self.curriculumStages = curriculumStages
        self.checkpoint = checkpoint
        self.regressionArtifacts = regressionArtifacts
        self.stressSuites = stressSuites
        self.physicsCorpora = physicsCorpora
        self.observabilityArtifacts = observabilityArtifacts
    }
}
