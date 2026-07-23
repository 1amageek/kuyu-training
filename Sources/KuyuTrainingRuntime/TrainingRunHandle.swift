import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public protocol TrainingRunHandle: Sendable {
    var runID: TrainingRunID { get }
    var progress: Progress { get }
    var events: AsyncStream<TrainingRunEvent> { get }

    func cancel()
    func wait() async throws -> TrainingRunSummary
    func detach() async
    func shutdown() async
}

public extension TrainingRunHandle {
    func detach() async {}
}
