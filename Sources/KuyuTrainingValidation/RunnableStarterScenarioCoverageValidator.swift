import KuyuCore
import KuyuScenarios
import KuyuTrainingContracts

public struct RunnableStarterScenarioCoverageValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable, CustomStringConvertible {
        case noRunnableStarterTemplates
        case missingPrimaryStage(templateID: String)
        case missingTaskProfile(templateID: String, stageID: String)
        case unsupportedTaskProfile(templateID: String, stageID: String, profileID: String)
        case unsupportedProfileFamily(templateID: String, stageID: String, family: TaskEvaluationProfileFamily)
        case unsupportedProfileTask(templateID: String, stageID: String, task: String)
        case invalidEpisodeCount(templateID: String, stageID: String, count: Int)
        case unresolvedSuite(templateID: String, stageID: String, suiteID: Int)
        case emptyScenarioCoverage(templateID: String, stageID: String, suiteID: Int)
        case duplicateScenarioKey(templateID: String, stageID: String, suiteID: Int, key: ScenarioKey)

        public var description: String {
            switch self {
            case .noRunnableStarterTemplates:
                return "no-runnable-starter-templates"
            case .missingPrimaryStage(let templateID):
                return "missing-primary-stage template=\(templateID)"
            case .missingTaskProfile(let templateID, let stageID):
                return "missing-task-profile template=\(templateID) stage=\(stageID)"
            case .unsupportedTaskProfile(let templateID, let stageID, let profileID):
                return "unsupported-task-profile template=\(templateID) stage=\(stageID) profile=\(profileID)"
            case .unsupportedProfileFamily(let templateID, let stageID, let family):
                return "unsupported-profile-family template=\(templateID) stage=\(stageID) family=\(family.rawValue)"
            case .unsupportedProfileTask(let templateID, let stageID, let task):
                return "unsupported-profile-task template=\(templateID) stage=\(stageID) task=\(task)"
            case .invalidEpisodeCount(let templateID, let stageID, let count):
                return "invalid-episode-count template=\(templateID) stage=\(stageID) count=\(count)"
            case .unresolvedSuite(let templateID, let stageID, let suiteID):
                return "unresolved-suite template=\(templateID) stage=\(stageID) suite=\(suiteID)"
            case .emptyScenarioCoverage(let templateID, let stageID, let suiteID):
                return "empty-scenario-coverage template=\(templateID) stage=\(stageID) suite=\(suiteID)"
            case .duplicateScenarioKey(let templateID, let stageID, let suiteID, let key):
                return "duplicate-scenario-key template=\(templateID) stage=\(stageID) suite=\(suiteID) scenario=\(key.scenarioId.rawValue) seed=\(key.seed.rawValue)"
            }
        }
    }

    public init() {}

    public func validate(catalog: LearningProjectTemplateCatalog = LearningProjectTemplateCatalog()) throws {
        let starters = catalog.templates.filter(\.isRunnableStarter)
        guard !starters.isEmpty else {
            throw ValidationError.noRunnableStarterTemplates
        }
        for template in starters {
            try validate(template)
        }
    }

    public func validate(_ template: LearningProjectTemplate) throws {
        guard template.isRunnableStarter else {
            return
        }
        guard let stage = template.primaryRunnableTrainingStage else {
            throw ValidationError.missingPrimaryStage(templateID: template.templateID)
        }
        guard let profileID = stage.taskProfileID ?? template.taskProfileID else {
            throw ValidationError.missingTaskProfile(templateID: template.templateID, stageID: stage.stageID)
        }

        let profile: TaskEvaluationProfile
        do {
            profile = try TaskEvaluationProfile.profile(profileID: profileID)
        } catch {
            throw ValidationError.unsupportedTaskProfile(
                templateID: template.templateID,
                stageID: stage.stageID,
                profileID: profileID
            )
        }

        guard profile.family == .referenceQuadrotor else {
            throw ValidationError.unsupportedProfileFamily(
                templateID: template.templateID,
                stageID: stage.stageID,
                family: profile.family
            )
        }

        let taskMode = try taskMode(for: profile, template: template, stage: stage)
        let episodeCount = stage.seedCount * stage.episodesPerSuite
        guard episodeCount > 0 else {
            throw ValidationError.invalidEpisodeCount(
                templateID: template.templateID,
                stageID: stage.stageID,
                count: episodeCount
            )
        }

        for suiteID in stage.suiteIDs {
            let definitions: [ReferenceQuadrotorScenarioDefinition]
            do {
                definitions = try ReferenceQuadrotorScenarioCatalog.scenarios(
                    for: taskMode,
                    suite: suiteID,
                    episodeCount: episodeCount
                )
            } catch {
                throw ValidationError.unresolvedSuite(
                    templateID: template.templateID,
                    stageID: stage.stageID,
                    suiteID: suiteID
                )
            }
            guard !definitions.isEmpty else {
                throw ValidationError.emptyScenarioCoverage(
                    templateID: template.templateID,
                    stageID: stage.stageID,
                    suiteID: suiteID
                )
            }
            try validateUniqueScenarioKeys(
                definitions,
                templateID: template.templateID,
                stageID: stage.stageID,
                suiteID: suiteID
            )
        }
    }

    private func taskMode(
        for profile: TaskEvaluationProfile,
        template: LearningProjectTemplate,
        stage: LearningProjectTrainingStage
    ) throws -> SimulationTaskMode {
        switch profile.task {
        case "attitude":
            return .attitude
        case "lift":
            return .lift
        case "singleLift":
            return .singleLift
        default:
            throw ValidationError.unsupportedProfileTask(
                templateID: template.templateID,
                stageID: stage.stageID,
                task: profile.task
            )
        }
    }

    private func validateUniqueScenarioKeys(
        _ definitions: [ReferenceQuadrotorScenarioDefinition],
        templateID: String,
        stageID: String,
        suiteID: Int
    ) throws {
        var keys = Set<ScenarioKey>()
        for definition in definitions {
            let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
            let (inserted, _) = keys.insert(key)
            guard inserted else {
                throw ValidationError.duplicateScenarioKey(
                    templateID: templateID,
                    stageID: stageID,
                    suiteID: suiteID,
                    key: key
                )
            }
        }
    }
}
