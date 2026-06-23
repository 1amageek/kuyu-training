import Foundation
import Testing
@testable import KuyuTraining

@Suite("ManagedTrainingRunHandle")
struct ManagedTrainingRunHandleTests {
    @Test(.timeLimit(.minutes(1))) func waitReturnsSummaryAndFinishesEventStream() async throws {
        let runID = TrainingRunID("managed-complete")
        let artifactRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("managed-complete", isDirectory: true)
        let expected = TrainingRunSummary(
            runID: runID,
            artifactRoot: artifactRoot,
            terminalState: .completed,
            generationCount: 1,
            candidateCount: 2
        )
        let handle = ManagedTrainingRunHandle(runID: runID) { emitter in
            emitter.emit(.iterationStarted(0))
            return expected
        }

        var iterator = handle.events.makeAsyncIterator()
        #expect(await iterator.next() == .iterationStarted(0))
        #expect(try await handle.wait() == expected)
        #expect(await iterator.next() == nil)
    }

    @Test(.timeLimit(.minutes(1))) func cancelFinishesEventStream() async throws {
        let runID = TrainingRunID("managed-cancel")
        let handle = ManagedTrainingRunHandle(runID: runID) { emitter in
            emitter.emit(.iterationStarted(0))
            try await Task.sleep(for: .seconds(60))
            return TrainingRunSummary(
                runID: runID,
                artifactRoot: FileManager.default.temporaryDirectory,
                terminalState: .completed
            )
        }

        var iterator = handle.events.makeAsyncIterator()
        #expect(await iterator.next() == .iterationStarted(0))
        handle.cancel()
        #expect(await iterator.next() == nil)
    }

    @Test(.timeLimit(.minutes(1))) func shutdownFinishesEventStream() async throws {
        let runID = TrainingRunID("managed-shutdown")
        let handle = ManagedTrainingRunHandle(runID: runID) { emitter in
            emitter.emit(.iterationStarted(0))
            try await Task.sleep(for: .seconds(60))
            return TrainingRunSummary(
                runID: runID,
                artifactRoot: FileManager.default.temporaryDirectory,
                terminalState: .completed
            )
        }

        var iterator = handle.events.makeAsyncIterator()
        #expect(await iterator.next() == .iterationStarted(0))
        await handle.shutdown()
        #expect(await iterator.next() == nil)
    }
}
