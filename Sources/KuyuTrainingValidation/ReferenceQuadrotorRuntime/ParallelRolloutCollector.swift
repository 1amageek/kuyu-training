import Foundation

public struct ParallelRolloutCollector: Sendable {
    public enum CollectorError: Error, Equatable {
        case invalidWorkerCount(Int)
    }

    public let runner: RolloutRunner
    public let workerCount: Int

    public init(runner: RolloutRunner, workerCount: Int = Self.defaultWorkerCount()) throws {
        guard workerCount > 0 else { throw CollectorError.invalidWorkerCount(workerCount) }
        self.runner = runner
        self.workerCount = workerCount
    }

    public static func defaultWorkerCount(activeProcessorCount: Int = ProcessInfo.processInfo.activeProcessorCount) -> Int {
        min(4, max(1, activeProcessorCount - 1))
    }
}
