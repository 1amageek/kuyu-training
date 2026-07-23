import Foundation

public protocol TrainingCheckpointReferenceResolving: Sendable {
    func reference(
        for checkpointURL: URL
    ) throws -> TrainingRunIterationRecord.CheckpointReference
}
