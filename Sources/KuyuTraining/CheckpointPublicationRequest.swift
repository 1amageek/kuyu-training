import Foundation

public struct CheckpointPublicationRequest: Sendable, Equatable {
    public let runID: String
    public let candidateID: String
    public let destination: ModelBundleReference
    public let artifactRoot: URL

    public init(
        runID: String,
        candidateID: String,
        destination: ModelBundleReference,
        artifactRoot: URL
    ) {
        self.runID = runID
        self.candidateID = candidateID
        self.destination = destination
        self.artifactRoot = artifactRoot
    }
}
