import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public enum KuyuProjectPackageError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidPackageExtension(path: String)
    case packageAlreadyExists(path: String)
    case missingProjectManifest(path: String)
    case schemaVersionMismatch(file: String, expected: Int, actual: Int)
    case emptyField(file: String, field: String)
    case missingReference(file: String, value: String)
    case mismatchedReference(file: String, field: String, expected: String, actual: String)
    case invalidTemplate(LearningProjectTemplateValidationError)

    public var description: String {
        switch self {
        case let .invalidPackageExtension(path):
            return "invalid-package-extension path=\(path)"
        case let .packageAlreadyExists(path):
            return "package-already-exists path=\(path)"
        case let .missingProjectManifest(path):
            return "missing-project-manifest path=\(path)"
        case let .schemaVersionMismatch(file, expected, actual):
            return "schema-version-mismatch file=\(file) expected=\(expected) actual=\(actual)"
        case let .emptyField(file, field):
            return "empty-field file=\(file) field=\(field)"
        case let .missingReference(file, value):
            return "missing-reference file=\(file) value=\(value)"
        case let .mismatchedReference(file, field, expected, actual):
            return "mismatched-reference file=\(file) field=\(field) expected=\(expected) actual=\(actual)"
        case let .invalidTemplate(error):
            return "invalid-template error=\(error.description)"
        }
    }
}
