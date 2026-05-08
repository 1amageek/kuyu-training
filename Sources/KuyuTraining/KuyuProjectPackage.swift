import Foundation

public struct KuyuProjectPackage: Sendable, Equatable {
    public let rootURL: URL
    public let manifest: KuyuProjectManifest
    public let selectedTemplate: LearningProjectTemplate
    public let defaultExperiment: KuyuProjectExperiment
    public let descriptorReference: LearningProjectDescriptorReference
    public let environmentReference: KuyuProjectEnvironmentReference
    public let sourceBundleReference: KuyuProjectBundleReference

    public init(
        rootURL: URL,
        manifest: KuyuProjectManifest,
        selectedTemplate: LearningProjectTemplate,
        defaultExperiment: KuyuProjectExperiment,
        descriptorReference: LearningProjectDescriptorReference,
        environmentReference: KuyuProjectEnvironmentReference,
        sourceBundleReference: KuyuProjectBundleReference
    ) {
        self.rootURL = rootURL
        self.manifest = manifest
        self.selectedTemplate = selectedTemplate
        self.defaultExperiment = defaultExperiment
        self.descriptorReference = descriptorReference
        self.environmentReference = environmentReference
        self.sourceBundleReference = sourceBundleReference
    }
}
