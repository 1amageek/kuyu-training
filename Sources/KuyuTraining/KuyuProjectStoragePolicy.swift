import Foundation

public enum KuyuProjectCandidateRetentionPolicy: String, Codable, Sendable, Equatable, CaseIterable {
    case acceptedOnly
    case elitesOnly
    case full
}

public struct KuyuProjectStoragePolicy: Codable, Sendable, Equatable {
    public let embedsModelBundles: Bool
    public let retainsRunArtifacts: Bool
    public let candidateCheckpointRetention: KuyuProjectCandidateRetentionPolicy

    public init(
        embedsModelBundles: Bool,
        retainsRunArtifacts: Bool,
        candidateCheckpointRetention: KuyuProjectCandidateRetentionPolicy
    ) {
        self.embedsModelBundles = embedsModelBundles
        self.retainsRunArtifacts = retainsRunArtifacts
        self.candidateCheckpointRetention = candidateCheckpointRetention
    }

    public static let runnableStarter = KuyuProjectStoragePolicy(
        embedsModelBundles: false,
        retainsRunArtifacts: true,
        candidateCheckpointRetention: .acceptedOnly
    )
}
