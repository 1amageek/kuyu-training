import Foundation

public enum LearningProjectTemplateValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedSchemaVersion(expected: Int, actual: Int)
    case emptyTemplateID
    case emptyDisplayName
    case emptyTask
    case emptyRobotManifestID
    case robotManifestPathRequired(source: LearningProjectRobotManifestSource)
    case invalidTaskProfile(expected: String, actual: String?)
    case unsupportedTaskProfile(task: String)
    case invalidObservationChannelCount(expected: Int, actual: Int)
    case emptyObservationSchemaID
    case duplicateObservationChannel(index: Int)
    case observationChannelCountMismatch(expected: Int, actual: Int)
    case invalidObservationContract(reason: String)
    case invalidActionContract(reason: String)
    case invalidPolicyContract(reason: String)
    case invalidCurriculum(reason: String)
    case invalidEvaluationGate(reason: String)
    case invalidComputeProfile(reason: String)

    public var description: String {
        switch self {
        case let .unsupportedSchemaVersion(expected, actual):
            return "unsupported-schema-version expected=\(expected) actual=\(actual)"
        case .emptyTemplateID:
            return "empty-template-id"
        case .emptyDisplayName:
            return "empty-display-name"
        case .emptyTask:
            return "empty-task"
        case .emptyRobotManifestID:
            return "empty-robot-manifest-id"
        case let .robotManifestPathRequired(source):
            return "robot-manifest-path-required source=\(source.rawValue)"
        case let .invalidTaskProfile(expected, actual):
            return "invalid-task-profile expected=\(expected) actual=\(actual ?? "nil")"
        case let .unsupportedTaskProfile(task):
            return "unsupported-task-profile task=\(task)"
        case let .invalidObservationChannelCount(expected, actual):
            return "invalid-observation-channel-count expected=\(expected) actual=\(actual)"
        case .emptyObservationSchemaID:
            return "empty-observation-schema-id"
        case let .duplicateObservationChannel(index):
            return "duplicate-observation-channel index=\(index)"
        case let .observationChannelCountMismatch(expected, actual):
            return "observation-channel-count-mismatch expected=\(expected) actual=\(actual)"
        case let .invalidObservationContract(reason):
            return "invalid-observation-contract reason=\(reason)"
        case let .invalidActionContract(reason):
            return "invalid-action-contract reason=\(reason)"
        case let .invalidPolicyContract(reason):
            return "invalid-policy-contract reason=\(reason)"
        case let .invalidCurriculum(reason):
            return "invalid-curriculum reason=\(reason)"
        case let .invalidEvaluationGate(reason):
            return "invalid-evaluation-gate reason=\(reason)"
        case let .invalidComputeProfile(reason):
            return "invalid-compute-profile reason=\(reason)"
        }
    }
}
