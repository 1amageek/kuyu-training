import Foundation
import KuyuTraining
import Testing

@Test func vectorizedBatchSpecDefinesPopulationWorldAndTensorShapes() throws {
    let spec = try VectorizedTrainingBatchSpec(
        populationSize: 100,
        worldCount: 4,
        rolloutHorizon: 256,
        historyLength: 32,
        observationDimension: 64,
        actionDimension: 4,
        actionEncoding: .ctbr,
        executionMode: .isolatedWorlds,
        requiresAccelerator: .metal
    )

    #expect(spec.actorObservationShape == [100, 4, 32, 64])
    #expect(spec.actionShape == [100, 4, 4])
    #expect(spec.requiresAccelerator == .metal)
}

@Test func vectorizedBatchSpecDoesNotOwnActionEncodingSemantics() throws {
    let spec = try VectorizedTrainingBatchSpec(
        populationSize: 100,
        worldCount: 4,
        rolloutHorizon: 256,
        historyLength: 32,
        observationDimension: 64,
        actionDimension: 3,
        actionEncoding: .ctbr,
        executionMode: .isolatedWorlds,
        requiresAccelerator: .metal
    )

    #expect(spec.actionShape == [100, 4, 3])
    #expect(spec.actionEncoding == .ctbr)
}

@Test func vectorizedBatchSpecAllowsSingleDriveDirectMotorShape() throws {
    let spec = try VectorizedTrainingBatchSpec(
        populationSize: 100,
        worldCount: 4,
        rolloutHorizon: 256,
        historyLength: 1,
        observationDimension: 8,
        actionDimension: 1,
        actionEncoding: .directMotor,
        executionMode: .sharedWorld,
        requiresAccelerator: .metal
    )

    #expect(spec.actionShape == [100, 4, 1])
    #expect(spec.actionEncoding == .directMotor)
}

@Test func vectorizedRolloutRequestRequiresOneCandidatePerPopulationSlot() throws {
    let spec = try VectorizedTrainingBatchSpec(
        populationSize: 2,
        worldCount: 1,
        rolloutHorizon: 4,
        historyLength: 2,
        observationDimension: 3,
        actionDimension: 4,
        actionEncoding: .ctbr,
        executionMode: .isolatedWorlds,
        requiresAccelerator: .metal
    )
    let candidates = [
        VectorizedCandidateReference(candidateID: "c0", candidate: "candidate-0")
    ]

    do {
        _ = try VectorizedRolloutRequest(
            batchSpec: spec,
            candidates: candidates,
            artifactDirectory: URL(fileURLWithPath: "/tmp/kuyu-vectorized-test"),
            randomSeed: 1
        )
        Issue.record("Expected population mismatch to throw.")
    } catch VectorizedRolloutRequestError.populationCountMismatch(let expected, let actual) {
        #expect(expected == 2)
        #expect(actual == 1)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func defaultVectorizedRolloutCollectorRunsPolicyWorldLoop() async throws {
    let spec = try VectorizedTrainingBatchSpec(
        populationSize: 2,
        worldCount: 1,
        rolloutHorizon: 3,
        historyLength: 2,
        observationDimension: 3,
        actionDimension: 4,
        actionEncoding: .ctbr,
        executionMode: .isolatedWorlds,
        requiresAccelerator: .metal
    )
    let request = try VectorizedRolloutRequest(
        batchSpec: spec,
        candidates: [
            VectorizedCandidateReference(candidateID: "c0", candidate: "candidate-0"),
            VectorizedCandidateReference(candidateID: "c1", candidate: "candidate-1")
        ],
        artifactDirectory: URL(fileURLWithPath: "/tmp/kuyu-vectorized-test"),
        randomSeed: 42
    )
    let collector = DefaultVectorizedRolloutCollector(
        policy: FakeVectorizedPolicy(),
        world: FakeVectorizedWorld()
    )

    let result = try await collector.collect(request: request)

    #expect(result.batchSpec.populationSize == 2)
    #expect(result.summaries.map(\.candidateID) == ["c0", "c1"])
    #expect(result.summaries.allSatisfy { $0.rolloutCount == 1 })
}

private struct FakeVectorizedPolicy: VectorizedPolicyEvaluating {
    typealias Candidate = String
    typealias ObservationBatch = [[Double]]
    typealias ActionBatch = [[Double]]

    func evaluateActions(
        candidates: [VectorizedCandidateReference<String>],
        observations: [[Double]],
        spec: VectorizedTrainingBatchSpec
    ) async throws -> [[Double]] {
        candidates.map { _ in [0.5, 0, 0, 0] }
    }
}

private struct FakeVectorizedWorld: VectorizedWorldSimulating {
    typealias Candidate = String
    typealias ObservationBatch = [[Double]]
    typealias ActionBatch = [[Double]]

    func reset(
        request: VectorizedRolloutRequest<String>
    ) async throws -> [[Double]] {
        request.candidates.map { _ in Array(repeating: 0, count: request.batchSpec.observationDimension) }
    }

    func step(
        actions: [[Double]],
        request: VectorizedRolloutRequest<String>
    ) async throws -> [[Double]] {
        request.candidates.map { _ in Array(repeating: 1, count: request.batchSpec.observationDimension) }
    }

    func finish(
        request: VectorizedRolloutRequest<String>
    ) async throws -> VectorizedRolloutBatchResult {
        let summaries = try request.candidates.enumerated().map { index, candidate in
            try VectorizedCandidateRolloutSummary(
                candidateID: candidate.candidateID,
                rewardAverage: Double(index),
                fitness: Double(index),
                taskPassRate: 1,
                safetyViolationRate: 0,
                rolloutCount: 1
            )
        }
        return try VectorizedRolloutBatchResult(
            batchSpec: request.batchSpec,
            summaries: summaries,
            artifactDirectory: request.artifactDirectory,
            elapsedSeconds: 0
        )
    }
}
