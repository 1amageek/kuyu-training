import Foundation

public struct CheckpointPublicationReceipt: Sendable, Equatable {
    public let runID: String
    public let candidateID: String
    public let sourceReference: EvolutionCheckpointReference
    public let destinationReference: EvolutionCheckpointReference

    public init(
        runID: String,
        candidateID: String,
        sourceReference: EvolutionCheckpointReference,
        destinationReference: EvolutionCheckpointReference
    ) {
        self.runID = runID
        self.candidateID = candidateID
        self.sourceReference = sourceReference
        self.destinationReference = destinationReference
    }
}
