public enum LearningProjectCurriculumStageResolverError: Error, Sendable, Equatable, CustomStringConvertible {
    case duplicateStageID(String)
    case missingDependency(stageID: String, dependencyID: String)

    public var description: String {
        switch self {
        case .duplicateStageID(let stageID):
            return "duplicate-stage-id stage=\(stageID)"
        case .missingDependency(let stageID, let dependencyID):
            return "missing-stage-dependency stage=\(stageID) dependency=\(dependencyID)"
        }
    }
}

public struct LearningProjectCurriculumStageResolver: Sendable {
    public init() {}

    public func runnableStages(
        in curriculum: LearningProjectCurriculum
    ) throws -> [LearningProjectTrainingStage] {
        try validateStageGraph(curriculum.trainingStages)
        return curriculum.trainingStages.filter { $0.taskProfileID != nil }
    }

    public func nextRunnableStage(
        in curriculum: LearningProjectCurriculum,
        completedStageIDs: Set<String>
    ) throws -> LearningProjectTrainingStage? {
        let runnableStages = try runnableStages(in: curriculum)
        return runnableStages.first { stage in
            !completedStageIDs.contains(stage.stageID)
                && stage.dependsOnStageIDs.allSatisfy { completedStageIDs.contains($0) }
        }
    }

    public func blockedRunnableStages(
        in curriculum: LearningProjectCurriculum,
        completedStageIDs: Set<String>
    ) throws -> [LearningProjectTrainingStage] {
        let runnableStages = try runnableStages(in: curriculum)
        return runnableStages.filter { stage in
            !completedStageIDs.contains(stage.stageID)
                && !stage.dependsOnStageIDs.allSatisfy { completedStageIDs.contains($0) }
        }
    }

    private func validateStageGraph(_ stages: [LearningProjectTrainingStage]) throws {
        var stageIDs = Set<String>()
        for stage in stages {
            guard stageIDs.insert(stage.stageID).inserted else {
                throw LearningProjectCurriculumStageResolverError.duplicateStageID(stage.stageID)
            }
        }
        for stage in stages {
            for dependencyID in stage.dependsOnStageIDs where !stageIDs.contains(dependencyID) {
                throw LearningProjectCurriculumStageResolverError.missingDependency(
                    stageID: stage.stageID,
                    dependencyID: dependencyID
                )
            }
        }
    }
}
