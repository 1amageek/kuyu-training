import Foundation

public struct KuyuProjectFactory: Sendable {
    private let now: @Sendable () -> Date
    private let idGenerator: @Sendable () -> String

    public init(
        now: @escaping @Sendable () -> Date = { Date() },
        idGenerator: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.now = now
        self.idGenerator = idGenerator
    }

    public func makeRunnableStarterProject(
        rootURL: URL,
        name: String,
        template: LearningProjectTemplate,
        sourceBundleURL: String = "model-bundles/source.manasbundle"
    ) throws -> KuyuProjectPackage {
        try KuyuProjectPackageWriter.validatePackageExtension(rootURL)
        let requiresStrictTemplateValidation = template.isRunnableStarter
        try LearningProjectTemplateValidator(
            requiresKnownTaskProfile: requiresStrictTemplateValidation
        ).validate(template)

        let timestamp = now()
        let experimentID = "default"
        let environmentID = "default"
        let sourceBundleID = "source"
        let projectID = "proj-\(idGenerator())"

        let manifest = KuyuProjectManifest(
            projectID: projectID,
            name: name,
            createdAt: timestamp,
            updatedAt: timestamp,
            defaultTemplateID: template.templateID,
            defaultExperimentID: experimentID,
            domains: [template.domain],
            robotManifestRefs: [template.robotManifest.robotManifestID],
            environmentRefs: [environmentID],
            experimentRefs: [experimentID],
            runRefs: [],
            modelBundleRefs: [sourceBundleID],
            storagePolicy: .runnableStarter,
            validationPolicy: KuyuProjectValidationPolicy(
                requiresStrictTemplateValidation: requiresStrictTemplateValidation,
                requiresRobotManifestHash: false,
                requiresModelBundleCompatibility: template.isRunnableStarter
            )
        )

        let experiment = KuyuProjectExperiment(
            experimentID: experimentID,
            templateID: template.templateID,
            name: template.displayName,
            summary: template.summary,
            task: template.task,
            domain: template.domain,
            tags: template.tags,
            curriculum: template.curriculum,
            trainingStrategy: template.trainingStrategy,
            evaluationGate: template.evaluationGate,
            observation: template.observation,
            action: template.action,
            compute: template.compute,
            createdAt: timestamp
        )

        let environment = KuyuProjectEnvironmentReference(
            environmentID: environmentID,
            displayName: "\(template.displayName) Environment",
            domain: template.domain,
            task: template.task,
            suiteIDs: template.curriculum.suiteIDs
        )

        let sourceBundle = KuyuProjectBundleReference(
            bundleID: sourceBundleID,
            role: .source,
            url: sourceBundleURL,
            contentHash: nil,
            requiredCompatibility: KuyuProjectBundleCompatibility(
                robotManifestID: template.robotManifest.robotManifestID,
                observationSchemaID: template.observation.schemaID,
                actionSchemaID: template.action.schemaID,
                driveCount: template.action.driveCount
            )
        )

        let package = KuyuProjectPackage(
            rootURL: rootURL,
            manifest: manifest,
            selectedTemplate: template,
            defaultExperiment: experiment,
            robotManifestReference: template.robotManifest,
            environmentReference: environment,
            sourceBundleReference: sourceBundle
        )
        try KuyuProjectPackageValidator().validate(package)
        return package
    }
}
