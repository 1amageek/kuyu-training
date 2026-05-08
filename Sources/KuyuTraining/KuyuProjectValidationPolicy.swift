import Foundation

public struct KuyuProjectValidationPolicy: Codable, Sendable, Equatable {
    public let requiresStrictTemplateValidation: Bool
    public let requiresDescriptorHash: Bool
    public let requiresModelBundleCompatibility: Bool

    public init(
        requiresStrictTemplateValidation: Bool,
        requiresDescriptorHash: Bool,
        requiresModelBundleCompatibility: Bool
    ) {
        self.requiresStrictTemplateValidation = requiresStrictTemplateValidation
        self.requiresDescriptorHash = requiresDescriptorHash
        self.requiresModelBundleCompatibility = requiresModelBundleCompatibility
    }

    public static let runnableStarter = KuyuProjectValidationPolicy(
        requiresStrictTemplateValidation: true,
        requiresDescriptorHash: false,
        requiresModelBundleCompatibility: true
    )
}
