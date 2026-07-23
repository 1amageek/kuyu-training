import Foundation

public extension TrainingRunDriver {
    /// Computes a stable SHA-256 digest over a checkpoint directory: regular
    /// files sorted by relative path, hashing `path\0content\0` per file.
    func checkpointReference(for checkpointURL: URL) throws -> TrainingRunIterationRecord.CheckpointReference {
        do {
            return try TrainingCheckpointReferenceResolver().reference(for: checkpointURL)
        } catch {
            throw DriverError.checkpointDigestFailed(
                path: checkpointURL.path,
                reason: String(describing: error)
            )
        }
    }
}
