import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public protocol AnyTrainingRunExecuting: Sendable {
    func start(_ request: TrainingRunRequest) async throws -> any TrainingRunHandle
    func resume(_ request: TrainingResumeRequest) async throws -> any TrainingRunHandle
    func reconnect(artifactRoot: URL) async throws -> (any TrainingRunHandle)?
    func continuationSelection(from artifactRoot: URL) throws -> TrainingContinuationSelection
    func validate(_ request: TrainingRunRequest) throws
    func validate(_ request: TrainingResumeRequest) throws
}

extension AnyTrainingRunExecuting {
    public func reconnect(artifactRoot: URL) async throws -> (any TrainingRunHandle)? {
        nil
    }
}
