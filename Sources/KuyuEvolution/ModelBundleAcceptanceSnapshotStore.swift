import Foundation
import KuyuTrainingContracts

public struct ModelBundleAcceptanceSnapshotStore: Sendable {
    public enum SnapshotError: Error, Sendable, Equatable {
        case sourceDigestMissing
    }

    private let publicationStore: ModelBundlePublicationStore

    public init(validator: any ModelBundlePublicationValidating) {
        self.publicationStore = ModelBundlePublicationStore(validator: validator)
    }

    public func snapshot(
        source: ModelBundleReference,
        runID: String,
        candidateID: String,
        artifactRoot: URL
    ) throws -> ModelBundleReference {
        guard let sourceDigest = source.contentHash else {
            throw SnapshotError.sourceDigestMissing
        }
        let snapshotURL = artifactRoot
            .appendingPathComponent("acceptance-snapshots", isDirectory: true)
            .appendingPathComponent(sourceDigest, isDirectory: true)
        let destination = ModelBundleReference(
            bundleID: source.bundleID,
            kind: .candidate,
            url: snapshotURL,
            contentHash: sourceDigest,
            robotManifestID: source.robotManifestID,
            observationSchemaID: source.observationSchemaID,
            actionSchemaID: source.actionSchemaID
        )
        let receipt = try publicationStore.publish(
            source: source.url,
            request: CheckpointPublicationRequest(
                runID: runID,
                candidateID: candidateID,
                expectedSourceDigest: sourceDigest,
                destination: destination,
                artifactRoot: artifactRoot
            )
        )
        return ModelBundleReference(
            bundleID: source.bundleID,
            kind: .candidate,
            url: receipt.destinationReference.checkpointURL,
            contentHash: receipt.destinationReference.sha256Digest,
            robotManifestID: source.robotManifestID,
            observationSchemaID: source.observationSchemaID,
            actionSchemaID: source.actionSchemaID
        )
    }
}
