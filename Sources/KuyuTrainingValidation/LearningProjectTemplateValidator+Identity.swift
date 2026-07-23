import Foundation
import KuyuTrainingContracts

extension LearningProjectTemplateValidator {
    func validateIdentity(_ template: LearningProjectTemplate) throws {
        if template.schemaVersion != LearningProjectTemplate.currentSchemaVersion {
            throw LearningProjectTemplateValidationError.unsupportedSchemaVersion(
                expected: LearningProjectTemplate.currentSchemaVersion,
                actual: template.schemaVersion
            )
        }
        if template.templateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LearningProjectTemplateValidationError.emptyTemplateID
        }
        if template.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LearningProjectTemplateValidationError.emptyDisplayName
        }
        if template.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LearningProjectTemplateValidationError.emptyTask
        }
    }

    func validateRobotManifest(_ robotManifest: LearningProjectRobotManifestReference) throws {
        if robotManifest.robotManifestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LearningProjectTemplateValidationError.emptyRobotManifestID
        }
        switch robotManifest.source {
        case .filePath, .remote:
            if robotManifest.path?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                throw LearningProjectTemplateValidationError.robotManifestPathRequired(source: robotManifest.source)
            }
        case .bundled, .generated:
            break
        }
    }
}
