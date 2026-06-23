import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

/// Lists run directories under a run root.
///
/// Directories without a parseable manifest are reported as `unreadable`
/// entries with the underlying error — never silently skipped. Readable
/// entries are sorted by `createdAt` descending; unreadable entries follow,
/// sorted by directory name.
public struct TrainingRunArchiveRegistry: Sendable {
    public let runRoot: URL

    public init(runRoot: URL) {
        self.runRoot = runRoot
    }

    public func list() throws -> [TrainingRunRegistryEntry] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: runRoot.path) else {
            return []
        }
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: runRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw TrainingRunContractError.invalidRunRoot(
                path: runRoot.path,
                reason: String(describing: error)
            )
        }
        var readable: [(entry: TrainingRunRegistryEntry, createdAt: Date)] = []
        var unreadable: [TrainingRunRegistryEntry] = []
        for url in entries {
            let isDirectory: Bool
            do {
                isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            } catch {
                unreadable.append(TrainingRunRegistryEntry(
                    directory: url,
                    content: .unreadable(reason: String(describing: error))
                ))
                continue
            }
            guard isDirectory else {
                unreadable.append(TrainingRunRegistryEntry(
                    directory: url,
                    content: .unreadable(reason: "not a directory")
                ))
                continue
            }
            let reader = TrainingRunArchiveReader(runDirectory: url)
            do {
                let manifest = try reader.loadManifest()
                readable.append((
                    TrainingRunRegistryEntry(directory: url, content: .readable(manifest)),
                    manifest.createdAt
                ))
            } catch {
                unreadable.append(TrainingRunRegistryEntry(
                    directory: url,
                    content: .unreadable(reason: String(describing: error))
                ))
            }
        }
        let sortedReadable = readable
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.entry.directory.lastPathComponent < rhs.entry.directory.lastPathComponent
            }
            .map(\.entry)
        let sortedUnreadable = unreadable.sorted {
            $0.directory.lastPathComponent < $1.directory.lastPathComponent
        }
        return sortedReadable + sortedUnreadable
    }
}
