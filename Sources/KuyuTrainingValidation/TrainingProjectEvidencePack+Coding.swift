import Foundation

extension TrainingProjectEvidencePack {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectID
        case createdAt
        case datasets
        case curriculumStages
        case checkpoint
        case regressionArtifacts
        case stressSuites
        case physicsCorpora
        case observabilityArtifacts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            projectID: try container.decode(String.self, forKey: .projectID),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            datasets: try container.decode([DatasetLineageRecord].self, forKey: .datasets),
            curriculumStages: try container.decode([CurriculumStageEvidence].self, forKey: .curriculumStages),
            checkpoint: try container.decode(CheckpointEvidence.self, forKey: .checkpoint),
            regressionArtifacts: try container.decode(
                [RegressionArtifactReference].self,
                forKey: .regressionArtifacts
            ),
            stressSuites: try container.decodeIfPresent([StressSuiteEvidence].self, forKey: .stressSuites) ?? [],
            physicsCorpora: try container.decodeIfPresent([PhysicsCorpusEvidence].self, forKey: .physicsCorpora) ?? [],
            observabilityArtifacts: try container.decodeIfPresent(
                [ObservabilityArtifactEvidence].self,
                forKey: .observabilityArtifacts
            ) ?? []
        )
        try TrainingProjectEvidencePackValidator().validate(self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(projectID, forKey: .projectID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(datasets, forKey: .datasets)
        try container.encode(curriculumStages, forKey: .curriculumStages)
        try container.encode(checkpoint, forKey: .checkpoint)
        try container.encode(regressionArtifacts, forKey: .regressionArtifacts)
        try container.encode(stressSuites, forKey: .stressSuites)
        try container.encode(physicsCorpora, forKey: .physicsCorpora)
        try container.encode(observabilityArtifacts, forKey: .observabilityArtifacts)
    }
}
