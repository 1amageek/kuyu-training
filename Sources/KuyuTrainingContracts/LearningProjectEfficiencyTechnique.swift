import Foundation

public enum LearningProjectEfficiencyTechniqueKind: String, Codable, Sendable, Equatable, CaseIterable {
    case teacherTrajectoryBootstrap
    case hindsightGoalRelabeling
    case modelBasedWarmStart
    case domainRandomization
    case residualPolicyRefinement
    case datasetAggregation
}

public struct LearningProjectEfficiencyTechnique: Codable, Sendable, Equatable {
    public let techniqueID: String
    public let kind: LearningProjectEfficiencyTechniqueKind
    public let sourceTitle: String
    public let sourceURL: String
    public let implementationGoal: String
    public let artifactRequirement: String

    public init(
        techniqueID: String,
        kind: LearningProjectEfficiencyTechniqueKind,
        sourceTitle: String,
        sourceURL: String,
        implementationGoal: String,
        artifactRequirement: String
    ) {
        self.techniqueID = techniqueID
        self.kind = kind
        self.sourceTitle = sourceTitle
        self.sourceURL = sourceURL
        self.implementationGoal = implementationGoal
        self.artifactRequirement = artifactRequirement
    }
}
