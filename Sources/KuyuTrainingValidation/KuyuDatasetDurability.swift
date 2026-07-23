import Darwin
import Foundation

enum KuyuDatasetDurability {
    static func synchronize(_ descriptor: Int32, path: URL, operation: String) throws {
        while true {
            if Darwin.fsync(descriptor) == 0 { return }
            if errno == EINTR { continue }
            throw KuyuDatasetArtifactError.synchronizationFailed(
                path: path,
                operation: operation,
                code: errno
            )
        }
    }
}
