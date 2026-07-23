import Foundation
import KuyuEvolution

public extension GeneratedTrainingArtifactCompatibilityVerifier {
    func evolutionPublicationProjection(
        for artifacts: EvolutionRunArtifactBundle
    ) -> EvolutionArtifactPublicationProjection {
        EvolutionArtifactPublicationProjection(artifacts: artifacts)
    }

    func validatedEvolutionPublicationProjection(
        in artifactDirectory: URL
    ) throws -> EvolutionArtifactPublicationProjection {
        try evolutionPublicationProjection(for: validatedEvolutionArtifacts(in: artifactDirectory))
    }

    func requireAcceptedEvolutionCheckpoint(
        _ projection: EvolutionArtifactPublicationProjection
    ) throws {
        guard projection.accepted else {
            throw VerificationError.evolutionCheckpointNotAccepted(projection.reasons)
        }
    }
}
