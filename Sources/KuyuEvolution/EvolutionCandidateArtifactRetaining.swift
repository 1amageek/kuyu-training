import Foundation

public protocol EvolutionCandidateArtifactRetaining: Sendable {
    func reconcile(in artifactDirectory: URL, expectedRunID: String) throws
    func recover(_ request: EvolutionCandidateArtifactRetentionRequest) throws
    func validate(_ request: EvolutionCandidateArtifactRetentionRequest) throws
    func retain(_ request: EvolutionCandidateArtifactRetentionRequest) throws
}
