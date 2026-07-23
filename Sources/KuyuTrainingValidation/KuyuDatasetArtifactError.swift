import Foundation
import KuyuTrainingContracts

public enum KuyuDatasetArtifactError: Error, Sendable, Equatable {
    case invalidConfiguration(field: String, value: Int)
    case posixFailure(path: URL, operation: String, code: Int32)
    case missingArtifact(URL)
    case nonDirectoryArtifact(URL)
    case symbolicLinkNotAllowed(URL)
    case missingFile(URL)
    case nonRegularFile(URL)
    case manifestTooLarge(path: URL, maximumBytes: Int, actualBytes: Int)
    case recordsTooLarge(path: URL, maximumBytes: Int64, actualBytes: Int64)
    case fileSizeUnavailable(URL)
    case manifestDecodeFailed(path: URL, reason: String)
    case manifestChangedDuringRead
    case streamOpenFailed(URL)
    case streamReadFailed(path: URL, reason: String)
    case emptyRecordLine(index: UInt64)
    case recordTooLarge(index: UInt64, maximumBytes: Int)
    case missingFinalNewline
    case recordDecodeFailed(index: UInt64, reason: String)
    case recordsDigestMismatch(expected: String, actual: String)
    case destinationExists(URL)
    case invalidDestinationParent(URL)
    case writeFailed(path: URL, operation: String, reason: String)
    case synchronizationFailed(path: URL, operation: String, code: Int32)
    case publicationFailed(source: URL, destination: URL, reason: String)
    case publishedButDurabilityUncertain(destination: URL, code: Int32)
    case operationAndCleanupFailed(operation: String, cleanup: String)
}
