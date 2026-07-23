import Darwin
import Foundation

enum KuyuDatasetPOSIX {
    struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    static func withDirectory<T>(
        at url: URL,
        _ operation: (Int32) throws -> T
    ) throws -> T {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw error(path: url, operation: "open directory")
        }
        do {
            try validateDirectory(descriptor, path: url)
        } catch {
            return try closeAfterFailure(descriptor, path: url, primary: error)
        }
        return try use(descriptor, path: url, operation)
    }

    static func withDirectory<T>(
        in parentDescriptor: Int32,
        name: String,
        path: URL,
        _ operation: (Int32) throws -> T
    ) throws -> T {
        let descriptor = name.withCString {
            Darwin.openat(parentDescriptor, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw error(path: path, operation: "open directory entry")
        }
        do {
            try validateDirectory(descriptor, path: path)
        } catch {
            return try closeAfterFailure(descriptor, path: path, primary: error)
        }
        return try use(descriptor, path: path, operation)
    }

    static func withRegularFile<T>(
        in directoryDescriptor: Int32,
        name: String,
        path: URL,
        _ operation: (Int32) throws -> T
    ) throws -> T {
        let descriptor = name.withCString {
            Darwin.openat(directoryDescriptor, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw error(path: path, operation: "open regular file")
        }
        do {
            _ = try regularFileSize(descriptor, path: path)
        } catch {
            return try closeAfterFailure(descriptor, path: path, primary: error)
        }
        return try use(descriptor, path: path, operation)
    }

    static func withCreatedFile<T>(
        in directoryDescriptor: Int32,
        name: String,
        path: URL,
        _ operation: (Int32) throws -> T
    ) throws -> T {
        let descriptor = name.withCString {
            Darwin.openat(
                directoryDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                mode_t(S_IRUSR | S_IWUSR)
            )
        }
        guard descriptor >= 0 else {
            throw error(path: path, operation: "create regular file")
        }
        return try use(descriptor, path: path, operation)
    }

    static func withUnlinkedTemporaryFile<T>(
        _ operation: (Int32, URL) throws -> T
    ) throws -> T {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuyu-dataset-snapshot-\(UUID().uuidString)")
        let descriptor = url.path.withCString {
            Darwin.open(
                $0,
                O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                mode_t(S_IRUSR | S_IWUSR)
            )
        }
        guard descriptor >= 0 else {
            throw error(path: url, operation: "create private snapshot")
        }
        let unlinkResult = url.path.withCString { Darwin.unlink($0) }
        guard unlinkResult == 0 else {
            return try closeAfterFailure(
                descriptor,
                path: url,
                primary: error(path: url, operation: "unlink private snapshot")
            )
        }
        return try use(descriptor, path: url) { try operation($0, url) }
    }

    static func makeDirectory(
        in parentDescriptor: Int32,
        name: String,
        path: URL
    ) throws {
        let result = name.withCString {
            Darwin.mkdirat(parentDescriptor, $0, mode_t(S_IRWXU))
        }
        guard result == 0 else {
            throw error(path: path, operation: "create staging directory")
        }
    }

    static func entryExists(in directoryDescriptor: Int32, name: String, path: URL) throws -> Bool {
        var status = stat()
        let result = name.withCString {
            Darwin.fstatat(directoryDescriptor, $0, &status, AT_SYMLINK_NOFOLLOW)
        }
        if result == 0 { return true }
        if errno == ENOENT { return false }
        throw error(path: path, operation: "inspect directory entry")
    }

    static func identity(of descriptor: Int32, path: URL) throws -> FileIdentity {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else {
            throw error(path: path, operation: "inspect descriptor identity")
        }
        return FileIdentity(device: status.st_dev, inode: status.st_ino)
    }

    static func identity(
        in directoryDescriptor: Int32,
        name: String,
        path: URL
    ) throws -> FileIdentity {
        var status = stat()
        let result = name.withCString {
            Darwin.fstatat(directoryDescriptor, $0, &status, AT_SYMLINK_NOFOLLOW)
        }
        guard result == 0 else {
            throw error(path: path, operation: "inspect entry identity")
        }
        return FileIdentity(device: status.st_dev, inode: status.st_ino)
    }

    static func publishDirectory(
        parentDescriptor: Int32,
        stagingName: String,
        stagingPath: URL,
        destinationName: String,
        destinationPath: URL
    ) throws {
        let result = stagingName.withCString { source in
            destinationName.withCString { destination in
                Darwin.renameatx_np(
                    parentDescriptor,
                    source,
                    parentDescriptor,
                    destination,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard result == 0 else {
            throw KuyuDatasetArtifactError.publicationFailed(
                source: stagingPath,
                destination: destinationPath,
                reason: "POSIX error \(errno)"
            )
        }
    }

    static func removeFileIfPresent(
        in directoryDescriptor: Int32,
        name: String,
        path: URL
    ) throws {
        let result = name.withCString { Darwin.unlinkat(directoryDescriptor, $0, 0) }
        if result == 0 || errno == ENOENT { return }
        throw error(path: path, operation: "remove staging file")
    }

    static func removeDirectoryIfPresent(
        in parentDescriptor: Int32,
        name: String,
        path: URL
    ) throws {
        let result = name.withCString {
            Darwin.unlinkat(parentDescriptor, $0, AT_REMOVEDIR)
        }
        if result == 0 || errno == ENOENT { return }
        throw error(path: path, operation: "remove staging directory")
    }

    static func regularFileSize(_ descriptor: Int32, path: URL) throws -> Int64 {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else {
            throw error(path: path, operation: "inspect regular file")
        }
        guard (status.st_mode & S_IFMT) == S_IFREG else {
            throw KuyuDatasetArtifactError.nonRegularFile(path)
        }
        guard status.st_size >= 0 else {
            throw KuyuDatasetArtifactError.fileSizeUnavailable(path)
        }
        return status.st_size
    }

    static func read(
        _ descriptor: Int32,
        into buffer: inout [UInt8],
        path: URL
    ) throws -> Int {
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count >= 0 { return count }
            if errno == EINTR { continue }
            throw error(path: path, operation: "read")
        }
    }

    static func write(
        _ data: Data,
        to descriptor: Int32,
        path: URL,
        operation: String
    ) throws {
        guard !data.isEmpty else { return }
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                if count > 0 {
                    offset += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    throw error(path: path, operation: operation)
                }
            }
        }
    }

    static func rewind(_ descriptor: Int32, path: URL) throws {
        guard Darwin.lseek(descriptor, 0, SEEK_SET) == 0 else {
            throw error(path: path, operation: "rewind")
        }
    }

    static func copy(
        from sourceDescriptor: Int32,
        sourcePath: URL,
        to destinationDescriptor: Int32,
        destinationPath: URL,
        chunkSize: Int,
        maximumBytes: Int64
    ) throws -> Int64 {
        try rewind(sourceDescriptor, path: sourcePath)
        try rewind(destinationDescriptor, path: destinationPath)
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        var total: Int64 = 0
        while true {
            let count = try read(sourceDescriptor, into: &buffer, path: sourcePath)
            if count == 0 { break }
            total += Int64(count)
            guard total <= maximumBytes else {
                throw KuyuDatasetArtifactError.recordsTooLarge(
                    path: sourcePath,
                    maximumBytes: maximumBytes,
                    actualBytes: total
                )
            }
            try write(
                Data(buffer[0..<count]),
                to: destinationDescriptor,
                path: destinationPath,
                operation: "copy private snapshot"
            )
        }
        try rewind(destinationDescriptor, path: destinationPath)
        return total
    }

    private static func validateDirectory(_ descriptor: Int32, path: URL) throws {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else {
            throw error(path: path, operation: "inspect directory")
        }
        guard (status.st_mode & S_IFMT) == S_IFDIR else {
            throw KuyuDatasetArtifactError.nonDirectoryArtifact(path)
        }
    }

    private static func use<T>(
        _ descriptor: Int32,
        path: URL,
        _ operation: (Int32) throws -> T
    ) throws -> T {
        let result: T
        do {
            result = try operation(descriptor)
        } catch {
            return try closeAfterFailure(descriptor, path: path, primary: error)
        }
        let closeResult = Darwin.close(descriptor)
        guard closeResult == 0 else {
            throw error(path: path, operation: "close")
        }
        return result
    }

    private static func closeAfterFailure<T>(
        _ descriptor: Int32,
        path: URL,
        primary: any Error
    ) throws -> T {
        let closeResult = Darwin.close(descriptor)
        guard closeResult == 0 else {
            throw KuyuDatasetArtifactError.operationAndCleanupFailed(
                operation: String(describing: primary),
                cleanup: String(describing: error(path: path, operation: "close"))
            )
        }
        throw primary
    }

    private static func error(path: URL, operation: String) -> KuyuDatasetArtifactError {
        .posixFailure(path: path, operation: operation, code: errno)
    }
}
