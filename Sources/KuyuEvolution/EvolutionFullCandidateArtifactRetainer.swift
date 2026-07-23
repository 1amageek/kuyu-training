import Foundation

public struct EvolutionFullCandidateArtifactRetainer: EvolutionCandidateArtifactRetaining {
    public init() {}

    public func reconcile(in artifactDirectory: URL, expectedRunID: String) throws {}

    public func recover(_ request: EvolutionCandidateArtifactRetentionRequest) throws {}

    public func validate(_ request: EvolutionCandidateArtifactRetentionRequest) throws {}

    public func retain(_ request: EvolutionCandidateArtifactRetentionRequest) throws {}
}
