import KuyuTrainingContracts
import KuyuTrainingValidation

public struct TrainingRunWorkerExecutionService: Sendable {
  public enum ExecutionError: Error, Sendable, Equatable {
    case stopMonitorFailed(String)
  }

  public typealias EventHandler = @Sendable (TrainingRunEvent) async throws -> Void

  private enum ExecutionTaskResult: Sendable {
    case summary(TrainingRunSummary)
    case eventStreamFinished
  }

  private let executor: any AnyTrainingRunExecuting

  public init(executor: any AnyTrainingRunExecuting) {
    self.executor = executor
  }

  public func execute(
    _ artifact: TrainingRunWorkerLaunchArtifact,
    workerAttemptIdentity: TrainingRunWorkerAttemptIdentity? = nil,
    stopRequest: TrainingRunWorkerStopRequest? = nil,
    onEvent: @escaping EventHandler = { _ in }
  ) async throws -> TrainingRunSummary {
    if let stopRequest {
      let isStopRequested: Bool
      do {
        isStopRequested = try stopRequest.isRequested()
      } catch {
        throw ExecutionError.stopMonitorFailed(String(describing: error))
      }
      if isStopRequested {
        let summary = TrainingRunSummary(
          runID: artifact.operation.runID,
          artifactRoot: artifact.operation.artifactRoot,
          terminalState: .cancelled
        )
        if let workerAttemptIdentity {
          _ = try TrainingRunSummaryOutcomeArtifactStore().write(
            summary: summary,
            expectedRunID: artifact.operation.runID,
            workerAttemptIdentity: workerAttemptIdentity,
            to: artifact.operation.artifactRoot
          )
        }
        return summary
      }
    }
    let lifecycle = TrainingRunLifecycleCoordinator()
    return try await withTaskCancellationHandler {
      let baseHandle: any TrainingRunHandle
      switch artifact.operation {
      case .start(let request):
        baseHandle = try await executor.start(request)
      case .resume(let request):
        baseHandle = try await executor.resume(request)
      }
      let handle: any TrainingRunHandle
      if let workerAttemptIdentity {
        handle = DurableSummaryTrainingRunHandle(
          wrapping: baseHandle,
          artifactRoot: artifact.operation.artifactRoot,
          workerAttemptIdentity: workerAttemptIdentity
        )
      } else {
        handle = baseHandle
      }
      try await lifecycle.register(handle)
      let stopMonitorTask = Task<String?, Never> {
        guard let stopRequest else { return nil }
        while !Task.isCancelled {
          do {
            if try stopRequest.isRequested() {
              handle.cancel()
              return nil
            }
            try await Task.sleep(for: .milliseconds(100))
          } catch is CancellationError {
            return nil
          } catch {
            handle.cancel()
            return String(describing: error)
          }
        }
        return nil
      }
      do {
        return try await withThrowingTaskGroup(
          of: ExecutionTaskResult.self,
          returning: TrainingRunSummary.self
        ) { group in
          group.addTask {
            .summary(try await lifecycle.waitForTermination())
          }
          group.addTask {
            do {
              for await event in handle.events {
                try await onEvent(event)
              }
              return .eventStreamFinished
            } catch {
              await lifecycle.requestCancellation()
              throw error
            }
          }

          while let result = try await group.next() {
            switch result {
            case .summary(let summary):
              stopMonitorTask.cancel()
              if let stopMonitorFailure = await stopMonitorTask.value {
                throw ExecutionError.stopMonitorFailed(stopMonitorFailure)
              }
              group.cancelAll()
              return summary
            case .eventStreamFinished:
              continue
            }
          }
          throw CancellationError()
        }
      } catch {
        stopMonitorTask.cancel()
        _ = await stopMonitorTask.value
        throw error
      }
    } onCancel: {
      Task {
        await lifecycle.requestCancellation()
      }
    }
  }
}
