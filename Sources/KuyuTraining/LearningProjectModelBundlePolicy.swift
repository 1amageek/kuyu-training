import Foundation

public enum LearningProjectSourceCheckpointPolicy: String, Codable, Sendable, Equatable, CaseIterable {
    case createStarter
    case requireExisting
    case optionalExisting
    case none
}

public struct LearningProjectModelBundlePolicy: Codable, Sendable, Equatable {
    public let sourceCheckpointPolicy: LearningProjectSourceCheckpointPolicy
    public let requiredBundleSchemaVersion: Int?
    public let requiresStrictPreflight: Bool
    public let requiresTaskCompatibleDriveCount: Bool

    public init(
        sourceCheckpointPolicy: LearningProjectSourceCheckpointPolicy,
        requiredBundleSchemaVersion: Int?,
        requiresStrictPreflight: Bool,
        requiresTaskCompatibleDriveCount: Bool
    ) {
        self.sourceCheckpointPolicy = sourceCheckpointPolicy
        self.requiredBundleSchemaVersion = requiredBundleSchemaVersion
        self.requiresStrictPreflight = requiresStrictPreflight
        self.requiresTaskCompatibleDriveCount = requiresTaskCompatibleDriveCount
    }
}
