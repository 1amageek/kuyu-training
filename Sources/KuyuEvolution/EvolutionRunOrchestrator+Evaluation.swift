import Foundation
import KuyuTrainingContracts

extension EvolutionRunOrchestrator {
    struct EvaluationBatch: Sendable {
        let fitness: [FitnessSummary]
        let traces: [EvolutionCandidateEvaluationTrace]
    }

    func evaluate(
        config: EvolutionRunConfig,
        population: EvolutionPopulation,
        generationArtifactDirectory: URL,
        progressReporter: (any TrainingProgressReporting)?,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)?
    ) async throws -> EvaluationBatch {
        if let batchEvaluator = evaluator as? any EvolutionCandidateBatchEvaluating {
            return try await evaluateWithBatchEvaluator(
                config: config,
                population: population,
                generationArtifactDirectory: generationArtifactDirectory,
                progressReporter: progressReporter,
                onEvent: onEvent,
                batchEvaluator: batchEvaluator
            )
        }
        if config.candidateEvaluationConcurrency <= 1 || population.candidates.count <= 1 {
            return try await evaluateSequentially(
                config: config,
                population: population,
                generationArtifactDirectory: generationArtifactDirectory,
                onEvent: onEvent
            )
        }
        return try await evaluateConcurrently(
            config: config,
            population: population,
            generationArtifactDirectory: generationArtifactDirectory,
            onEvent: onEvent
        )
    }

    private func evaluateWithBatchEvaluator(
        config: EvolutionRunConfig,
        population: EvolutionPopulation,
        generationArtifactDirectory: URL,
        progressReporter: (any TrainingProgressReporting)?,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)?,
        batchEvaluator: any EvolutionCandidateBatchEvaluating
    ) async throws -> EvaluationBatch {
        var records: [FitnessSummary] = []
        var traces: [EvolutionCandidateEvaluationTrace] = []
        records.reserveCapacity(population.candidates.count)
        traces.reserveCapacity(population.candidates.count)
        let evaluatesPopulationAsSingleOperation = batchEvaluator is any EvolutionPopulationBatchEvaluating
        let batchSize = evaluatesPopulationAsSingleOperation
            ? population.candidates.count
            : max(1, min(config.candidateEvaluationConcurrency, population.candidates.count))
        let batchCount = population.candidates.count / batchSize
            + (population.candidates.count % batchSize == 0 ? 0 : 1)
        let recorder = EvolutionEvaluationTraceRecorder()
        var nextIndex = 0
        var batchIndex = 0
        while nextIndex < population.candidates.count {
            try Task.checkCancellation()
            let batchEnd = min(nextIndex + batchSize, population.candidates.count)
            let candidates = Array(population.candidates[nextIndex..<batchEnd])
            let populationBatchStartedAt = Date()
            var starts: [String: (startedAt: Date, activeEvaluationCountAtStart: Int)] = [:]
            if evaluatesPopulationAsSingleOperation {
                for candidate in candidates {
                    starts[candidate.candidateID] = (populationBatchStartedAt, 1)
                }
            } else {
                for candidate in candidates {
                    starts[candidate.candidateID] = await recorder.begin()
                }
            }
            let summaries = try await batchEvaluator.evaluateCandidates(
                request: try EvolutionCandidateBatchEvaluationRequest(
                    config: config,
                    candidates: candidates,
                    generationArtifactDirectory: generationArtifactDirectory,
                    workerCount: config.workerCount,
                    batchIndex: batchIndex,
                    batchCount: batchCount,
                    populationSize: population.candidates.count
                ),
                progressReporter: progressReporter
            )
            guard summaries.count == candidates.count else {
                throw RunError.evaluationFailed(
                    "batch-evaluation-count-mismatch expected=\(candidates.count) actual=\(summaries.count)"
                )
            }
            for candidate in candidates {
                guard let summary = summaries.first(where: { $0.candidateID == candidate.candidateID }) else {
                    throw RunError.evaluationFailed("batch-evaluation-missing-candidate \(candidate.candidateID)")
                }
                onEvent?(.candidateEvaluated(summary))
                let started = starts[candidate.candidateID] ?? (
                    startedAt: Date(),
                    activeEvaluationCountAtStart: 1
                )
                let trace: EvolutionCandidateEvaluationTrace
                if evaluatesPopulationAsSingleOperation {
                    trace = EvolutionCandidateEvaluationTrace(
                        runID: config.runID,
                        generationIndex: candidate.generationIndex,
                        candidateID: candidate.candidateID,
                        requestedConcurrency: 1,
                        activeEvaluationCountAtStart: 1,
                        startedAt: started.startedAt,
                        completedAt: Date()
                    )
                } else {
                    trace = await recorder.end(
                        runID: config.runID,
                        generationIndex: candidate.generationIndex,
                        candidateID: candidate.candidateID,
                        requestedConcurrency: batchSize,
                        started: started
                    )
                }
                records.append(summary)
                traces.append(trace)
            }
            nextIndex = batchEnd
            batchIndex += 1
        }
        return EvaluationBatch(fitness: records, traces: traces)
    }

    private func evaluateSequentially(
        config: EvolutionRunConfig,
        population: EvolutionPopulation,
        generationArtifactDirectory: URL,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)?
    ) async throws -> EvaluationBatch {
        var records: [FitnessSummary] = []
        var traces: [EvolutionCandidateEvaluationTrace] = []
        records.reserveCapacity(population.candidates.count)
        traces.reserveCapacity(population.candidates.count)
        let recorder = EvolutionEvaluationTraceRecorder()
        for candidate in population.candidates {
            try Task.checkCancellation()
            let started = await recorder.begin()
            let summary = try await evaluator.evaluateCandidate(request: EvolutionCandidateEvaluationRequest(
                config: config,
                candidate: candidate,
                generationArtifactDirectory: generationArtifactDirectory,
                workerCount: config.workerCount
            ))
            onEvent?(.candidateEvaluated(summary))
            let trace = await recorder.end(
                runID: config.runID,
                generationIndex: candidate.generationIndex,
                candidateID: candidate.candidateID,
                requestedConcurrency: 1,
                started: started
            )
            records.append(summary)
            traces.append(trace)
            try Task.checkCancellation()
        }
        return EvaluationBatch(fitness: records, traces: traces)
    }

    private func evaluateConcurrently(
        config: EvolutionRunConfig,
        population: EvolutionPopulation,
        generationArtifactDirectory: URL,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)?
    ) async throws -> EvaluationBatch {
        var records = Array<FitnessSummary?>(repeating: nil, count: population.candidates.count)
        var traces = Array<EvolutionCandidateEvaluationTrace?>(repeating: nil, count: population.candidates.count)
        let evaluator = evaluator
        let concurrency = max(1, min(config.candidateEvaluationConcurrency, population.candidates.count))
        let recorder = EvolutionEvaluationTraceRecorder()
        var nextIndex = 0
        while nextIndex < population.candidates.count {
            try Task.checkCancellation()
            let batchEnd = min(nextIndex + concurrency, population.candidates.count)
            try await withThrowingTaskGroup(of: (Int, FitnessSummary, EvolutionCandidateEvaluationTrace).self) { group in
                for index in nextIndex..<batchEnd {
                    let candidate = population.candidates[index]
                    group.addTask {
                        try Task.checkCancellation()
                        let started = await recorder.begin()
                        let summary = try await evaluator.evaluateCandidate(request: EvolutionCandidateEvaluationRequest(
                            config: config,
                            candidate: candidate,
                            generationArtifactDirectory: generationArtifactDirectory,
                            workerCount: config.workerCount
                        ))
                        onEvent?(.candidateEvaluated(summary))
                        let trace = await recorder.end(
                            runID: config.runID,
                            generationIndex: candidate.generationIndex,
                            candidateID: candidate.candidateID,
                            requestedConcurrency: concurrency,
                            started: started
                        )
                        try Task.checkCancellation()
                        return (index, summary, trace)
                    }
                }
                for try await (index, summary, trace) in group {
                    records[index] = summary
                    traces[index] = trace
                }
            }
            nextIndex = batchEnd
        }
        return EvaluationBatch(
            fitness: records.compactMap { $0 },
            traces: traces.compactMap { $0 }
        )
    }
}
