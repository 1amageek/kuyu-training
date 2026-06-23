import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public protocol TrainingRunHandle {
    var runID: TrainingRunID { get }
    var progress: Progress { get }
    var events: AsyncStream<TrainingRunEvent> { get }

    func cancel()
    func wait() async throws -> TrainingRunSummary
    func shutdown() async
}
