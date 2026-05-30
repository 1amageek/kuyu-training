import Foundation

public struct KuyuProjectValidationPolicy: Codable, Sendable, Equatable {
    public let requiresStrictTemplateValidation: Bool
    public let requiresRobotManifestHash: Bool
    public let requiresModelBundleCompatibility: Bool

    public init(
        requiresStrictTemplateValidation: Bool,
        requiresRobotManifestHash: Bool,
        requiresModelBundleCompatibility: Bool
    ) {
        self.requiresStrictTemplateValidation = requiresStrictTemplateValidation
        self.requiresRobotManifestHash = requiresRobotManifestHash
        self.requiresModelBundleCompatibility = requiresModelBundleCompatibility
    }

    public static let runnableStarter = KuyuProjectValidationPolicy(
        requiresStrictTemplateValidation: true,
        requiresRobotManifestHash: false,
        requiresModelBundleCompatibility: true
    )
}
