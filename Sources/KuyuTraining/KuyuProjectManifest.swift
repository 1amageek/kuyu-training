import Foundation

public struct KuyuProjectManifest: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let projectID: String
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date
    public let defaultTemplateID: String
    public let defaultExperimentID: String
    public let domains: [AutonomousOperationDomain]
    public let descriptorRefs: [String]
    public let environmentRefs: [String]
    public let experimentRefs: [String]
    public let runRefs: [String]
    public let modelBundleRefs: [String]
    public let storagePolicy: KuyuProjectStoragePolicy
    public let validationPolicy: KuyuProjectValidationPolicy

    public init(
        schemaVersion: Int = KuyuProjectManifest.currentSchemaVersion,
        projectID: String,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        defaultTemplateID: String,
        defaultExperimentID: String,
        domains: [AutonomousOperationDomain],
        descriptorRefs: [String],
        environmentRefs: [String],
        experimentRefs: [String],
        runRefs: [String],
        modelBundleRefs: [String],
        storagePolicy: KuyuProjectStoragePolicy,
        validationPolicy: KuyuProjectValidationPolicy
    ) {
        self.schemaVersion = schemaVersion
        self.projectID = projectID
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.defaultTemplateID = defaultTemplateID
        self.defaultExperimentID = defaultExperimentID
        self.domains = domains
        self.descriptorRefs = descriptorRefs
        self.environmentRefs = environmentRefs
        self.experimentRefs = experimentRefs
        self.runRefs = runRefs
        self.modelBundleRefs = modelBundleRefs
        self.storagePolicy = storagePolicy
        self.validationPolicy = validationPolicy
    }
}
