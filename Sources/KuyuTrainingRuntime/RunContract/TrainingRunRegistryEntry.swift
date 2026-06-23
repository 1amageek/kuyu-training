import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

/// One run directory found under the run root.
///
/// Directories whose manifest cannot be read are reported as `unreadable`
/// with the underlying reason — they are never silently skipped.
public struct TrainingRunRegistryEntry: Sendable {
    public enum Content: Sendable {
        case readable(TrainingRunManifest)
        case unreadable(reason: String)
    }

    public let directory: URL
    public let content: Content

    public init(directory: URL, content: Content) {
        self.directory = directory
        self.content = content
    }

    /// Manifest when readable; nil otherwise.
    public var manifest: TrainingRunManifest? {
        switch content {
        case .readable(let manifest):
            return manifest
        case .unreadable:
            return nil
        }
    }
}
