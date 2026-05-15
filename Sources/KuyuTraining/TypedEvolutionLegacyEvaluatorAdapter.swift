import Foundation

public struct TypedEvolutionLegacyEvaluatorAdapter<Backend: TypedTrainingBackend>: EvolutionCandidateEvaluating
where
    Backend.Candidate == GenomeCandidate,
    Backend.Observation == TrainingNoObservation,
    Backend.Action == TrainingNoAction,
    Backend.Fitness == Double
{
    private let backend: Backend

    public init(backend: Backend) {
        self.backend = backend
    }

    public func evaluateCandidate(request: EvolutionCandidateEvaluationRequest) async throws -> FitnessSummary {
        let evaluation = try await backend.evaluate(
            request.candidate,
            in: TrainingEvaluationContext(
                runID: request.config.runID,
                taskProfileID: request.config.taskID,
                artifactRoot: request.generationArtifactDirectory,
                seed: request.config.commonRandomSeed,
                workerCount: request.workerCount
            )
        )
        return FitnessSummary(
            runID: request.config.runID,
            generationIndex: request.candidate.generationIndex,
            candidateID: evaluation.candidateID,
            taskID: request.config.taskID,
            scalarFitness: evaluation.fitness,
            rewardAverage: evaluation.rewardAverage ?? evaluation.fitness,
            taskPassRate: evaluation.taskPassRate ?? 0,
            safetyViolationRate: evaluation.safetyRate.map { 1 - $0 } ?? 0,
            holdTimeRatio: evaluation.holdTimeRatio,
            altitudeErrorRatio: evaluation.altitudeErrorRatio,
            failureReasons: evaluation.failureReasons
        )
    }
}
