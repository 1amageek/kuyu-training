import Foundation
import KuyuTraining
import Testing

@Test func kuyuProjectFactoryCreatesRunnableStarterPackage() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-project-package-\(UUID().uuidString)", isDirectory: true)
        .appendingPathExtension("kuyu")
    let factory = KuyuProjectFactory(
        now: { Date(timeIntervalSince1970: 1_000) },
        idGenerator: { "fixed" }
    )

    let package = try factory.makeRunnableStarterProject(
        rootURL: rootURL,
        name: "Drone Autonomy",
        template: .droneAutonomyStarter
    )

    #expect(package.manifest.projectID == "proj-fixed")
    #expect(package.manifest.defaultTemplateID == "aerial-drone-autonomy-starter-v1")
    #expect(package.defaultExperiment.experimentID == "default")
    #expect(package.sourceBundleReference.requiredCompatibility.driveCount == 4)
    #expect(package.sourceBundleReference.url == "model-bundles/source.bundle")
    #expect(package.selectedTemplate.isRunnableStarter)
    #expect(package.selectedTemplate.curriculum.trainingStages.count >= 5)
    #expect(package.manifest.validationPolicy.requiresStrictTemplateValidation)
    #expect(package.manifest.validationPolicy.requiresModelBundleCompatibility)
}

@Test func kuyuProjectFactoryDoesNotRequireModelBundleForDesignOnlyTemplate() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-project-design-\(UUID().uuidString)", isDirectory: true)
        .appendingPathExtension("kuyu")
    let factory = KuyuProjectFactory(
        now: { Date(timeIntervalSince1970: 1_000) },
        idGenerator: { "design" }
    )

    let package = try factory.makeRunnableStarterProject(
        rootURL: rootURL,
        name: "Ground Robot",
        template: .groundRobotPointNavigation
    )

    #expect(package.selectedTemplate.taskProfileID == nil)
    #expect(!package.manifest.validationPolicy.requiresStrictTemplateValidation)
    #expect(!package.manifest.validationPolicy.requiresModelBundleCompatibility)
}

@Test func kuyuProjectPackageWriterAndLoaderRoundTripProjectJSON() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-project-roundtrip-\(UUID().uuidString)", isDirectory: true)
        .appendingPathExtension("kuyu")
    let package = try KuyuProjectFactory(
        now: { Date(timeIntervalSince1970: 1_000) },
        idGenerator: { "roundtrip" }
    ).makeRunnableStarterProject(
        rootURL: rootURL,
        name: "Drone Autonomy",
        template: .droneAutonomyStarter
    )

    try KuyuProjectPackageWriter().write(package)
    let loaded = try KuyuProjectPackageLoader().load(from: rootURL)

    #expect(loaded.manifest == package.manifest)
    #expect(loaded.selectedTemplate == package.selectedTemplate)
    #expect(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("project.json").path))
}

@Test func kuyuProjectPackageLoaderRejectsMissingProjectJSON() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("missing-project-\(UUID().uuidString)", isDirectory: true)
        .appendingPathExtension("kuyu")
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

    do {
        _ = try KuyuProjectPackageLoader().load(from: rootURL)
        Issue.record("Expected missing project.json to throw.")
    } catch KuyuProjectPackageError.missingProjectManifest(let path) {
        #expect(path.hasSuffix("project.json"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func kuyuProjectPackageRejectsNonKuyuExtension() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("not-a-project-\(UUID().uuidString)", isDirectory: true)
        .appendingPathExtension("folder")

    do {
        _ = try KuyuProjectFactory().makeRunnableStarterProject(
            rootURL: rootURL,
            name: "Invalid",
            template: .droneAutonomyStarter
        )
        Issue.record("Expected invalid package extension to throw.")
    } catch KuyuProjectPackageError.invalidPackageExtension(let path) {
        #expect(path.hasSuffix(".folder"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func kuyuProjectPackageValidatorRejectsBundleReferenceFileAsBundleURL() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("bundle-file-url-project-\(UUID().uuidString)", isDirectory: true)
        .appendingPathExtension("kuyu")
    let package = try KuyuProjectFactory().makeRunnableStarterProject(
        rootURL: rootURL,
        name: "Drone Autonomy",
        template: .droneAutonomyStarter
    )
    let invalidBundle = KuyuProjectBundleReference(
        bundleID: package.sourceBundleReference.bundleID,
        role: package.sourceBundleReference.role,
        url: "model-bundles/source.bundle-ref.json",
        contentHash: package.sourceBundleReference.contentHash,
        requiredCompatibility: package.sourceBundleReference.requiredCompatibility
    )
    let invalidPackage = KuyuProjectPackage(
        rootURL: package.rootURL,
        manifest: package.manifest,
        selectedTemplate: package.selectedTemplate,
        defaultExperiment: package.defaultExperiment,
        robotManifestReference: package.robotManifestReference,
        environmentReference: package.environmentReference,
        sourceBundleReference: invalidBundle
    )

    do {
        try KuyuProjectPackageValidator().validate(invalidPackage)
        Issue.record("Expected source bundle reference file URL to throw.")
    } catch KuyuProjectPackageError.mismatchedReference(let file, let field, let expected, let actual) {
        #expect(file == "model-bundles/source.bundle-ref.json")
        #expect(field == "url")
        #expect(expected == "model bundle directory")
        #expect(actual == "model-bundles/source.bundle-ref.json")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func kuyuProjectPackageValidatorRejectsMismatchedTemplateReference() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("mismatched-project-\(UUID().uuidString)", isDirectory: true)
        .appendingPathExtension("kuyu")
    let package = try KuyuProjectFactory().makeRunnableStarterProject(
        rootURL: rootURL,
        name: "Drone Autonomy",
        template: .droneAutonomyStarter
    )
    let manifest = KuyuProjectManifest(
        projectID: package.manifest.projectID,
        name: package.manifest.name,
        createdAt: package.manifest.createdAt,
        updatedAt: package.manifest.updatedAt,
        defaultTemplateID: "wrong-template",
        defaultExperimentID: package.manifest.defaultExperimentID,
        domains: package.manifest.domains,
        robotManifestRefs: package.manifest.robotManifestRefs,
        environmentRefs: package.manifest.environmentRefs,
        experimentRefs: package.manifest.experimentRefs,
        runRefs: package.manifest.runRefs,
        modelBundleRefs: package.manifest.modelBundleRefs,
        storagePolicy: package.manifest.storagePolicy,
        validationPolicy: package.manifest.validationPolicy
    )
    let invalidPackage = KuyuProjectPackage(
        rootURL: package.rootURL,
        manifest: manifest,
        selectedTemplate: package.selectedTemplate,
        defaultExperiment: package.defaultExperiment,
        robotManifestReference: package.robotManifestReference,
        environmentReference: package.environmentReference,
        sourceBundleReference: package.sourceBundleReference
    )

    do {
        try KuyuProjectPackageValidator().validate(invalidPackage)
        Issue.record("Expected default template mismatch to throw.")
    } catch KuyuProjectPackageError.mismatchedReference(let file, let field, let expected, let actual) {
        #expect(file == "project.json")
        #expect(field == "defaultTemplateID")
        #expect(expected == "aerial-drone-autonomy-starter-v1")
        #expect(actual == "wrong-template")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
