import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public struct KuyuProjectPackageValidator: Sendable {
    public init() {}

    public func validate(_ package: KuyuProjectPackage) throws {
        try KuyuProjectPackageWriter.validatePackageExtension(package.rootURL)
        try validateManifest(package.manifest)
        try validateTemplate(package.selectedTemplate, policy: package.manifest.validationPolicy)
        try validateExperiment(package.defaultExperiment, manifest: package.manifest, template: package.selectedTemplate)
        try validateRobotManifest(package.robotManifestReference, manifest: package.manifest, template: package.selectedTemplate)
        try validateEnvironment(package.environmentReference, manifest: package.manifest, template: package.selectedTemplate)
        try validateBundle(package.sourceBundleReference, manifest: package.manifest, template: package.selectedTemplate)
    }

    private func validateManifest(_ manifest: KuyuProjectManifest) throws {
        if manifest.schemaVersion != KuyuProjectManifest.currentSchemaVersion {
            throw KuyuProjectPackageError.schemaVersionMismatch(
                file: "project.json",
                expected: KuyuProjectManifest.currentSchemaVersion,
                actual: manifest.schemaVersion
            )
        }
        try requireNonEmpty(manifest.projectID, file: "project.json", field: "projectID")
        try requireNonEmpty(manifest.name, file: "project.json", field: "name")
        try requireNonEmpty(manifest.defaultTemplateID, file: "project.json", field: "defaultTemplateID")
        try requireNonEmpty(manifest.defaultExperimentID, file: "project.json", field: "defaultExperimentID")
        try requireContains(manifest.experimentRefs, manifest.defaultExperimentID, file: "project.json")
        try requireContains(manifest.modelBundleRefs, "source", file: "project.json")
    }

    private func validateTemplate(
        _ template: LearningProjectTemplate,
        policy: KuyuProjectValidationPolicy
    ) throws {
        do {
        try LearningProjectTemplateValidator(
                requiresKnownTaskProfile: policy.requiresStrictTemplateValidation
            ).validate(template)
        } catch let error as LearningProjectTemplateValidationError {
            throw KuyuProjectPackageError.invalidTemplate(error)
        }
    }

    private func validateExperiment(
        _ experiment: KuyuProjectExperiment,
        manifest: KuyuProjectManifest,
        template: LearningProjectTemplate
    ) throws {
        if experiment.schemaVersion != KuyuProjectExperiment.currentSchemaVersion {
            throw KuyuProjectPackageError.schemaVersionMismatch(
                file: "experiments/default/experiment.json",
                expected: KuyuProjectExperiment.currentSchemaVersion,
                actual: experiment.schemaVersion
            )
        }
        try requireContains(manifest.experimentRefs, experiment.experimentID, file: "project.json")
        try requireMatch(manifest.defaultTemplateID, template.templateID, file: "project.json", field: "defaultTemplateID")
        try requireMatch(experiment.templateID, template.templateID, file: "experiments/default/experiment.json", field: "templateID")
        try requireMatch(experiment.task, template.task, file: "experiments/default/experiment.json", field: "task")
    }

    private func validateRobotManifest(
        _ robotManifest: LearningProjectRobotManifestReference,
        manifest: KuyuProjectManifest,
        template: LearningProjectTemplate
    ) throws {
        try requireContains(manifest.robotManifestRefs, robotManifest.robotManifestID, file: "project.json")
        try requireMatch(
            robotManifest.robotManifestID,
            template.robotManifest.robotManifestID,
            file: "robot-manifests/default/robot-manifest-ref.json",
            field: "robotManifestID"
        )
    }

    private func validateEnvironment(
        _ environment: KuyuProjectEnvironmentReference,
        manifest: KuyuProjectManifest,
        template: LearningProjectTemplate
    ) throws {
        try requireContains(manifest.environmentRefs, environment.environmentID, file: "project.json")
        try requireMatch(environment.task, template.task, file: "environments/default/environment.json", field: "task")
    }

    private func validateBundle(
        _ bundle: KuyuProjectBundleReference,
        manifest: KuyuProjectManifest,
        template: LearningProjectTemplate
    ) throws {
        if bundle.schemaVersion != KuyuProjectBundleReference.currentSchemaVersion {
            throw KuyuProjectPackageError.schemaVersionMismatch(
                file: "model-bundles/source.bundle-ref.json",
                expected: KuyuProjectBundleReference.currentSchemaVersion,
                actual: bundle.schemaVersion
            )
        }
        try requireContains(manifest.modelBundleRefs, bundle.bundleID, file: "project.json")
        try requireNonEmpty(bundle.url, file: "model-bundles/source.bundle-ref.json", field: "url")
        if bundle.url.hasSuffix(".json") {
            throw KuyuProjectPackageError.mismatchedReference(
                file: "model-bundles/source.bundle-ref.json",
                field: "url",
                expected: "model bundle directory",
                actual: bundle.url
            )
        }
        try requireMatch(
            bundle.requiredCompatibility.robotManifestID,
            template.robotManifest.robotManifestID,
            file: "model-bundles/source.bundle-ref.json",
            field: "robotManifestID"
        )
        try requireMatch(
            bundle.requiredCompatibility.observationSchemaID,
            template.observation.schemaID,
            file: "model-bundles/source.bundle-ref.json",
            field: "observationSchemaID"
        )
        try requireMatch(
            bundle.requiredCompatibility.actionSchemaID,
            template.action.schemaID,
            file: "model-bundles/source.bundle-ref.json",
            field: "actionSchemaID"
        )
    }

    private func requireNonEmpty(_ value: String, file: String, field: String) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw KuyuProjectPackageError.emptyField(file: file, field: field)
        }
    }

    private func requireContains(_ values: [String], _ value: String, file: String) throws {
        if !values.contains(value) {
            throw KuyuProjectPackageError.missingReference(file: file, value: value)
        }
    }

    private func requireMatch(_ actual: String, _ expected: String, file: String, field: String) throws {
        if actual != expected {
            throw KuyuProjectPackageError.mismatchedReference(
                file: file,
                field: field,
                expected: expected,
                actual: actual
            )
        }
    }
}
