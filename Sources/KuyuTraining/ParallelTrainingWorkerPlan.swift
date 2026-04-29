import Foundation

public struct ParallelTrainingWorkerAssignment: Sendable, Codable, Equatable {
    public let workerIndex: Int
    public let snapshot: WorkerSnapshot
    public let rolloutShardURL: URL

    public init(
        workerIndex: Int,
        snapshot: WorkerSnapshot,
        rolloutShardURL: URL
    ) {
        self.workerIndex = workerIndex
        self.snapshot = snapshot
        self.rolloutShardURL = rolloutShardURL
    }
}

public struct ParallelTrainingWorkerPlan: Sendable, Codable, Equatable {
    public let runID: String
    public let sourceSnapshot: TrainingBackendSnapshot?
    public let workerCount: Int
    public let assignments: [ParallelTrainingWorkerAssignment]

    public init(
        runID: String,
        sourceSnapshot: TrainingBackendSnapshot?,
        workerCount: Int,
        assignments: [ParallelTrainingWorkerAssignment]
    ) {
        self.runID = runID
        self.sourceSnapshot = sourceSnapshot
        self.workerCount = max(1, workerCount)
        self.assignments = assignments
    }
}

public struct ParallelTrainingWorkerPlanBuilder: Sendable {
    public enum PlanError: Error, Sendable, Equatable {
        case assignmentCountMismatch(expected: Int, actual: Int)
        case workerIndexMismatch(expected: Int, actual: Int)
    }

    public init() {}

    public func build(
        runID: String,
        workerCount: Int,
        sourceSnapshot: TrainingBackendSnapshot?,
        rolloutRoot: URL,
        snapshotProvider: any SnapshotProviding
    ) async throws -> ParallelTrainingWorkerPlan {
        let normalizedWorkerCount = max(1, workerCount)
        var assignments: [ParallelTrainingWorkerAssignment] = []
        assignments.reserveCapacity(normalizedWorkerCount)
        for workerIndex in 0..<normalizedWorkerCount {
            let lease = try await snapshotProvider.leaseSnapshot(workerIndex: workerIndex)
            guard lease.snapshot.workerIndex == workerIndex else {
                throw PlanError.workerIndexMismatch(
                    expected: workerIndex,
                    actual: lease.snapshot.workerIndex
                )
            }
            assignments.append(ParallelTrainingWorkerAssignment(
                workerIndex: workerIndex,
                snapshot: lease.snapshot,
                rolloutShardURL: rolloutRoot.appendingPathComponent("worker-\(workerIndex)", isDirectory: true)
            ))
        }
        guard assignments.count == normalizedWorkerCount else {
            throw PlanError.assignmentCountMismatch(
                expected: normalizedWorkerCount,
                actual: assignments.count
            )
        }
        return ParallelTrainingWorkerPlan(
            runID: runID,
            sourceSnapshot: sourceSnapshot,
            workerCount: normalizedWorkerCount,
            assignments: assignments
        )
    }
}
