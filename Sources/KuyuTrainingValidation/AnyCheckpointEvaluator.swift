import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
public struct AnyCheckpointEvaluator: CheckpointEvaluating {
    private let evaluateHandler: @Sendable (CheckpointEvaluationRequest) async throws -> CheckpointEvaluationArtifact

    public init<Evaluator: CheckpointEvaluating>(_ evaluator: Evaluator) {
        self.evaluateHandler = { request in
            try await evaluator.evaluateCheckpoint(request: request)
        }
    }

    public init(
        evaluate: @escaping @Sendable (CheckpointEvaluationRequest) async throws -> CheckpointEvaluationArtifact
    ) {
        self.evaluateHandler = evaluate
    }

    public func evaluateCheckpoint(request: CheckpointEvaluationRequest) async throws -> CheckpointEvaluationArtifact {
        try await evaluateHandler(request)
    }
}
