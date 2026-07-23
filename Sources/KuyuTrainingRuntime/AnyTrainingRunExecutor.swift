import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public struct AnyTrainingRunExecutor: AnyTrainingRunExecuting {
    private let startHandler: @Sendable (TrainingRunRequest) async throws -> any TrainingRunHandle
    private let resumeHandler: @Sendable (TrainingResumeRequest) async throws -> any TrainingRunHandle
    private let reconnectHandler: @Sendable (URL) async throws -> (any TrainingRunHandle)?
    private let continuationSelectionHandler: @Sendable (URL) throws -> TrainingContinuationSelection
    private let validateHandler: @Sendable (TrainingRunRequest) throws -> Void
    private let validateResumeHandler: @Sendable (TrainingResumeRequest) throws -> Void

    public init<Executor: AnyTrainingRunExecuting>(_ executor: Executor) {
        self.startHandler = { request in
            try await executor.start(request)
        }
        self.resumeHandler = { request in
            try await executor.resume(request)
        }
        self.reconnectHandler = { artifactRoot in
            try await executor.reconnect(artifactRoot: artifactRoot)
        }
        self.continuationSelectionHandler = { artifactRoot in
            try executor.continuationSelection(from: artifactRoot)
        }
        self.validateHandler = { request in
            try executor.validate(request)
        }
        self.validateResumeHandler = { request in
            try executor.validate(request)
        }
    }

    public init(
        start: @escaping @Sendable (TrainingRunRequest) async throws -> any TrainingRunHandle,
        resume: @escaping @Sendable (TrainingResumeRequest) async throws -> any TrainingRunHandle,
        continuationSelection: @escaping @Sendable (URL) throws -> TrainingContinuationSelection,
        validate: @escaping @Sendable (TrainingRunRequest) throws -> Void,
        validateResume: @escaping @Sendable (TrainingResumeRequest) throws -> Void,
        reconnect: @escaping @Sendable (URL) async throws -> (any TrainingRunHandle)? = { _ in nil }
    ) {
        self.startHandler = start
        self.resumeHandler = resume
        self.reconnectHandler = reconnect
        self.continuationSelectionHandler = continuationSelection
        self.validateHandler = validate
        self.validateResumeHandler = validateResume
    }

    public func start(_ request: TrainingRunRequest) async throws -> any TrainingRunHandle {
        try await startHandler(request)
    }

    public func resume(_ request: TrainingResumeRequest) async throws -> any TrainingRunHandle {
        try await resumeHandler(request)
    }

    public func reconnect(artifactRoot: URL) async throws -> (any TrainingRunHandle)? {
        try await reconnectHandler(artifactRoot)
    }

    public func continuationSelection(from artifactRoot: URL) throws -> TrainingContinuationSelection {
        try continuationSelectionHandler(artifactRoot)
    }

    public func validate(_ request: TrainingRunRequest) throws {
        try validateHandler(request)
    }

    public func validate(_ request: TrainingResumeRequest) throws {
        try validateResumeHandler(request)
    }
}
