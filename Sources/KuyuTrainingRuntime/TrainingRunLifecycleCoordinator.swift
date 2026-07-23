import KuyuTrainingContracts

public actor TrainingRunLifecycleCoordinator {
    public enum State: String, Sendable, Equatable {
        case starting
        case active
        case cancelling
        case terminal
    }

    public enum LifecycleError: Error, Sendable, Equatable {
        case handleAlreadyRegistered
        case handleNotRegistered
        case waitAlreadyStarted
    }

    private var handle: (any TrainingRunHandle)?
    private var cancellationRequested = false
    private var waitStarted = false
    private var state: State = .starting

    public init() {}

    public func register(_ handle: any TrainingRunHandle) throws {
        guard self.handle == nil else {
            throw LifecycleError.handleAlreadyRegistered
        }
        self.handle = handle
        if cancellationRequested {
            state = .cancelling
            handle.cancel()
        } else {
            state = .active
        }
    }

    public func requestCancellation() {
        guard state != .terminal, !cancellationRequested else { return }
        cancellationRequested = true
        state = .cancelling
        handle?.cancel()
    }

    public func waitForTermination() async throws -> TrainingRunSummary {
        guard let handle else {
            throw LifecycleError.handleNotRegistered
        }
        guard !waitStarted else {
            throw LifecycleError.waitAlreadyStarted
        }
        waitStarted = true
        do {
            let summary = try await handle.wait()
            await handle.shutdown()
            state = .terminal
            return summary
        } catch {
            await handle.shutdown()
            state = .terminal
            throw error
        }
    }

    public func currentState() -> State {
        state
    }
}
