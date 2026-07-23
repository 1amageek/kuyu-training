import Foundation
import Synchronization
import Testing
@testable import KuyuTraining

@Suite("TrainingRunLifecycleCoordinator")
struct TrainingRunLifecycleCoordinatorTests {
    @Test func cancellationBeforeRegistrationCancelsRegisteredHandle() async throws {
        let coordinator = TrainingRunLifecycleCoordinator()
        let handle = LifecycleRecordingTrainingRunHandle(runID: TrainingRunID("cancel-before-register"))

        await coordinator.requestCancellation()
        try await coordinator.register(handle)

        #expect(handle.cancelCount == 1)
        #expect(await coordinator.currentState() == .cancelling)
    }

    @Test func cancellationAfterRegistrationIsDeliveredOnce() async throws {
        let coordinator = TrainingRunLifecycleCoordinator()
        let handle = LifecycleRecordingTrainingRunHandle(runID: TrainingRunID("cancel-after-register"))
        try await coordinator.register(handle)

        await coordinator.requestCancellation()
        await coordinator.requestCancellation()

        #expect(handle.cancelCount == 1)
    }

    @Test func waitOwnsHandleCompletionAndShutdown() async throws {
        let coordinator = TrainingRunLifecycleCoordinator()
        let handle = LifecycleRecordingTrainingRunHandle(runID: TrainingRunID("wait"))
        try await coordinator.register(handle)

        let summary = try await coordinator.waitForTermination()

        #expect(summary.runID == handle.runID)
        #expect(handle.waitCount == 1)
        #expect(handle.shutdownCount == 1)
        #expect(await coordinator.currentState() == .terminal)
    }

    @Test func duplicateHandleRegistrationIsRejected() async throws {
        let coordinator = TrainingRunLifecycleCoordinator()
        try await coordinator.register(LifecycleRecordingTrainingRunHandle(runID: TrainingRunID("first")))

        await #expect(throws: TrainingRunLifecycleCoordinator.LifecycleError.handleAlreadyRegistered) {
            try await coordinator.register(LifecycleRecordingTrainingRunHandle(runID: TrainingRunID("second")))
        }
    }
}

private final class LifecycleRecordingTrainingRunHandle: TrainingRunHandle, Sendable {
    private struct State: Sendable {
        var cancelCount = 0
        var waitCount = 0
        var shutdownCount = 0
    }

    let runID: TrainingRunID
    let progress = Progress(totalUnitCount: 1)
    let events: AsyncStream<TrainingRunEvent>

    private let state = Mutex(State())

    var cancelCount: Int { state.withLock { $0.cancelCount } }
    var waitCount: Int { state.withLock { $0.waitCount } }
    var shutdownCount: Int { state.withLock { $0.shutdownCount } }

    init(runID: TrainingRunID) {
        self.runID = runID
        let stream = AsyncStream<TrainingRunEvent>.makeStream()
        stream.continuation.finish()
        events = stream.stream
    }

    func cancel() {
        state.withLock { $0.cancelCount += 1 }
    }

    func wait() async throws -> TrainingRunSummary {
        state.withLock { $0.waitCount += 1 }
        return TrainingRunSummary(
            runID: runID,
            artifactRoot: FileManager.default.temporaryDirectory,
            terminalState: .completed
        )
    }

    func shutdown() async {
        state.withLock { $0.shutdownCount += 1 }
    }
}
