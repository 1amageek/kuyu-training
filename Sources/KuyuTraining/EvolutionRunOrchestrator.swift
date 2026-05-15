import Foundation

public enum EvolutionRunEvent: Sendable, Equatable {
    case started(EvolutionRunManifest)
    case populationSeeded(EvolutionPopulation)
    case generationStarted(Int)
    case candidateEvaluated(FitnessSummary)
    case generationCompleted(PopulationGenerationRecord)
    case completed(EvolutionRunResult)
}

public struct EvolutionRunResult: Sendable, Equatable {
    public let manifest: EvolutionRunManifest
    public let generations: [PopulationGenerationRecord]
    public let candidates: [GenomeCandidate]
    public let fitness: [FitnessSummary]
    public let eliteArchive: EvolutionEliteArchive
    public let qualityDiversityArchive: EvolutionQualityDiversityArchive
    public let lineage: [EvolutionLineageRecord]
    public let evaluationTraces: [EvolutionCandidateEvaluationTrace]

    public init(
        manifest: EvolutionRunManifest,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        eliteArchive: EvolutionEliteArchive,
        qualityDiversityArchive: EvolutionQualityDiversityArchive,
        lineage: [EvolutionLineageRecord],
        evaluationTraces: [EvolutionCandidateEvaluationTrace] = []
    ) {
        self.manifest = manifest
        self.generations = generations
        self.candidates = candidates
        self.fitness = fitness
        self.eliteArchive = eliteArchive
        self.qualityDiversityArchive = qualityDiversityArchive
        self.lineage = lineage
        self.evaluationTraces = evaluationTraces
    }
}

public struct EvolutionRunOrchestrator {
    public enum RunError: Error, Sendable, Equatable {
        case emptyPopulation(Int)
        case backendFailed(String)
        case evaluationFailed(String)
        case artifactWriteFailed(String)
    }

    public let backend: any EvolutionaryTrainingBackend
    public let evaluator: any EvolutionCandidateEvaluating
    public let artifactWriter: any EvolutionArtifactWriting
    public let parentSelectionPolicy: EvolutionParentSelectionPolicy
    public let noveltyScoringPolicy: EvolutionNoveltyScoringPolicy

    public init(
        backend: any EvolutionaryTrainingBackend,
        evaluator: any EvolutionCandidateEvaluating,
        artifactWriter: any EvolutionArtifactWriting = EvolutionArtifactWriter(),
        parentSelectionPolicy: EvolutionParentSelectionPolicy = EvolutionParentSelectionPolicy(),
        noveltyScoringPolicy: EvolutionNoveltyScoringPolicy = EvolutionNoveltyScoringPolicy()
    ) {
        self.backend = backend
        self.evaluator = evaluator
        self.artifactWriter = artifactWriter
        self.parentSelectionPolicy = parentSelectionPolicy
        self.noveltyScoringPolicy = noveltyScoringPolicy
    }

    public init<Backend: TypedTrainingBackend>(
        typedBackend: Backend,
        checkpoint: ModelBundleReference,
        artifactWriter: any EvolutionArtifactWriting = EvolutionArtifactWriter(),
        parentSelectionPolicy: EvolutionParentSelectionPolicy = EvolutionParentSelectionPolicy(),
        noveltyScoringPolicy: EvolutionNoveltyScoringPolicy = EvolutionNoveltyScoringPolicy()
    )
    where
        Backend.Candidate == GenomeCandidate,
        Backend.Checkpoint == ModelBundleReference,
        Backend.Observation == TrainingNoObservation,
        Backend.Action == TrainingNoAction,
        Backend.Fitness == Double
    {
        self.init(
            backend: TypedEvolutionLegacyBackendAdapter(
                backend: typedBackend,
                checkpoint: checkpoint
            ),
            evaluator: TypedEvolutionLegacyEvaluatorAdapter(backend: typedBackend),
            artifactWriter: artifactWriter,
            parentSelectionPolicy: parentSelectionPolicy,
            noveltyScoringPolicy: noveltyScoringPolicy
        )
    }

    public func run(
        config: EvolutionRunConfig,
        gatePolicy: EvolutionGatePolicy? = nil,
        artifactDirectory: URL,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)? = nil
    ) async -> EvolutionRunResult {
        let manifest = EvolutionRunManifest(
            runID: config.runID,
            taskID: config.taskID,
            descriptorID: config.descriptorID,
            descriptorHash: config.descriptorHash,
            configHash: config.configHash,
            policyID: config.policyID,
            populationSize: config.populationSize,
            generationCount: config.generationCount,
            eliteCount: config.eliteCount,
            workerCount: config.workerCount,
            candidateEvaluationConcurrency: config.candidateEvaluationConcurrency,
            searchStrategy: config.searchStrategy,
            bootstrapSource: config.bootstrapSource,
            worldModelUsage: config.worldModelUsage,
            antitheticSampling: config.antitheticSampling,
            commonRandomSeed: config.commonRandomSeed,
            mutationRate: config.mutationRate,
            mutationNoiseScale: config.mutationNoiseScale,
            parentCheckpointID: config.parentCheckpointID,
            startedAt: Date(),
            terminalState: .running
        )
        onEvent?(.started(manifest))
        do {
            try Task.checkCancellation()
            let seededPopulation = try await backend.seedPopulation(request: EvolutionSeedRequest(
                config: config,
                artifactDirectory: artifactDirectory,
                mutationRate: config.mutationRate,
                mutationNoiseScale: config.mutationNoiseScale,
                commonRandomSeed: commonRandomSeed(config: config, generationIndex: 0)
            ))
            onEvent?(.populationSeeded(seededPopulation))
            return await runGenerations(
                manifest: manifest,
                config: config,
                initialPopulation: seededPopulation,
                gatePolicy: gatePolicy ?? EvolutionGatePolicy(eliteCount: config.eliteCount),
                artifactDirectory: artifactDirectory,
                onEvent: onEvent
            )
        } catch is CancellationError {
            return await finish(
                manifest: manifest,
                state: .cancelled,
                failureReason: "cancelled",
                generations: [],
                candidates: [],
                fitness: [],
                artifactDirectory: artifactDirectory,
                onEvent: onEvent
            )
        } catch {
            return await finish(
                manifest: manifest,
                state: .failed,
                failureReason: "evolution-backend-failed: \(error)",
                generations: [],
                candidates: [],
                fitness: [],
                artifactDirectory: artifactDirectory,
                onEvent: onEvent
            )
        }
    }

    private func runGenerations(
        manifest: EvolutionRunManifest,
        config: EvolutionRunConfig,
        initialPopulation: EvolutionPopulation,
        gatePolicy: EvolutionGatePolicy,
        artifactDirectory: URL,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)?
    ) async -> EvolutionRunResult {
        var currentPopulation = initialPopulation
        var allGenerations: [PopulationGenerationRecord] = []
        var allCandidates: [GenomeCandidate] = []
        var allFitness: [FitnessSummary] = []
        var allEvaluationTraces: [EvolutionCandidateEvaluationTrace] = []
        var bestAcceptedFitness: FitnessSummary?
        var finalGateReport: EvolutionGateReport?
        var incumbentCandidateID: String?
        var incumbentFitness: Double?
        var mutationRate = config.mutationRate
        var mutationNoiseScale = config.mutationNoiseScale
        var earlyStoppingState = EvolutionEarlyStoppingState(config: config.earlyStopping)

        for generationIndex in 0..<config.generationCount {
            if Task.isCancelled {
                return await finish(
                    manifest: manifest,
                    state: .cancelled,
                    failureReason: "cancelled",
                    generations: allGenerations,
                    candidates: allCandidates,
                    fitness: allFitness,
                    evaluationTraces: allEvaluationTraces,
                    bestFitness: bestAcceptedFitness,
                    artifactDirectory: artifactDirectory,
                    onEvent: onEvent
                )
            }
            onEvent?(.generationStarted(generationIndex))
            guard !currentPopulation.candidates.isEmpty else {
                return await finish(
                    manifest: manifest,
                    state: .failed,
                    failureReason: "empty-population-\(generationIndex)",
                    generations: allGenerations,
                    candidates: allCandidates,
                    fitness: allFitness,
                    artifactDirectory: artifactDirectory,
                    onEvent: onEvent
                )
            }
            let generationDirectory = artifactDirectory
                .appendingPathComponent("generations", isDirectory: true)
                .appendingPathComponent("generation-\(generationIndex)", isDirectory: true)
            allCandidates.append(contentsOf: currentPopulation.candidates)
            let generationFitness: [FitnessSummary]
            do {
                let evaluation = try await evaluate(
                    config: config,
                    population: currentPopulation,
                    generationArtifactDirectory: generationDirectory,
                    onEvent: onEvent
                )
                generationFitness = noveltyScoringPolicy.score(
                    currentGeneration: evaluation.fitness,
                    archive: allFitness
                )
                allEvaluationTraces.append(contentsOf: evaluation.traces)
            } catch is CancellationError {
                let cancelledFitness = evaluationCancellationFitness(
                    config: config,
                    candidates: currentPopulation.candidates
                )
                let cancelledTraces = evaluationCancellationTraces(
                    config: config,
                    candidates: currentPopulation.candidates
                )
                return await finish(
                    manifest: manifest,
                    state: .cancelled,
                    failureReason: "cancelled",
                    generations: allGenerations,
                    candidates: allCandidates,
                    fitness: allFitness + cancelledFitness,
                    evaluationTraces: allEvaluationTraces + cancelledTraces,
                    bestFitness: bestAcceptedFitness,
                    artifactDirectory: artifactDirectory,
                    onEvent: onEvent
                )
            } catch {
                let failedFitness = evaluationFailureFitness(
                    config: config,
                    candidates: currentPopulation.candidates,
                    error: error
                )
                let failedTraces = evaluationFailureTraces(
                    config: config,
                    candidates: currentPopulation.candidates
                )
                for summary in failedFitness {
                    onEvent?(.candidateEvaluated(summary))
                }
                return await finish(
                    manifest: manifest,
                    state: .failed,
                    failureReason: "evolution-evaluation-failed: \(error)",
                    generations: allGenerations,
                    candidates: allCandidates,
                    fitness: allFitness + failedFitness,
                    evaluationTraces: allEvaluationTraces + failedTraces,
                    artifactDirectory: artifactDirectory,
                    onEvent: onEvent
                )
            }
            allFitness.append(contentsOf: generationFitness)
            if incumbentCandidateID == nil,
               let incumbentCandidate = currentPopulation.candidates.first(where: { $0.isIncumbent == true }),
               let summary = generationFitness.first(where: { $0.candidateID == incumbentCandidate.candidateID }) {
                incumbentCandidateID = incumbentCandidate.candidateID
                incumbentFitness = summary.scalarFitness
            }
            let gateReport = gatePolicy.report(
                runID: config.runID,
                generationIndex: generationIndex,
                fitness: generationFitness,
                incumbentCandidateID: incumbentCandidateID,
                incumbentFitness: incumbentFitness
            )
            finalGateReport = gateReport
            if gateReport.accepted {
                bestAcceptedFitness = bestFitnessSummary(
                    current: bestAcceptedFitness,
                    candidateFitness: generationFitness.filter { gateReport.eliteCandidateIDs.contains($0.candidateID) }
                )
            }
            let generationRecord = PopulationGenerationRecord(
                runID: config.runID,
                generationIndex: generationIndex,
                candidateCount: currentPopulation.candidates.count,
                evaluatedCandidateCount: generationFitness.count,
                eliteCandidateIDs: gateReport.eliteCandidateIDs,
                bestCandidateID: gateReport.bestCandidateID,
                bestFitness: gateReport.bestFitness,
                incumbentCandidateID: gateReport.incumbentCandidateID,
                incumbentFitness: gateReport.incumbentFitness,
                bestVsIncumbentDelta: gateReport.bestVsIncumbentDelta,
                minimumImprovementOverIncumbent: gateReport.minimumImprovementOverIncumbent,
                incumbentImproved: incumbentImproved(gateReport: gateReport),
                qualityDiversityCellCount: EvolutionQualityDiversityArchiveBuilder()
                    .build(runID: config.runID, fitness: allFitness)
                    .cells
                    .count,
                mutationRate: mutationRate,
                mutationNoiseScale: mutationNoiseScale,
                accepted: gateReport.accepted,
                rejectionReasons: gateReport.rejectionReasons
            )
            allGenerations.append(generationRecord)
            onEvent?(.generationCompleted(generationRecord))
            if let stopReason = earlyStoppingState.record(fitness: generationFitness),
               generationIndex < config.generationCount - 1 {
                return await finish(
                    manifest: manifest,
                    state: bestAcceptedFitness == nil ? .rejected : .completed,
                    failureReason: stopReason,
                    generations: allGenerations,
                    candidates: allCandidates,
                    fitness: allFitness,
                    evaluationTraces: allEvaluationTraces,
                    bestFitness: bestAcceptedFitness,
                    artifactDirectory: artifactDirectory,
                    onEvent: onEvent
                )
            }
            if generationIndex == config.generationCount - 1 {
                break
            }
            let nextSchedule = nextMutationSchedule(
                config: config,
                currentMutationRate: mutationRate,
                currentMutationNoiseScale: mutationNoiseScale,
                gateReport: gateReport
            )
            mutationRate = nextSchedule.mutationRate
            mutationNoiseScale = nextSchedule.mutationNoiseScale
            let parentCandidateIDs = parentSelectionPolicy.parentCandidateIDs(
                config: config,
                eliteCandidateIDs: gateReport.eliteCandidateIDs,
                generationFitness: generationFitness
            )
            do {
                try Task.checkCancellation()
                currentPopulation = try await backend.produceNextGeneration(request: EvolutionGenerationRequest(
                    config: config,
                    previousPopulation: currentPopulation,
                    fitness: generationFitness,
                    eliteCandidateIDs: gateReport.eliteCandidateIDs,
                    parentCandidateIDs: parentCandidateIDs,
                    mutationRate: mutationRate,
                    mutationNoiseScale: mutationNoiseScale,
                    commonRandomSeed: commonRandomSeed(config: config, generationIndex: generationIndex + 1),
                    generationArtifactDirectory: generationDirectory
                ))
            } catch is CancellationError {
                return await finish(
                    manifest: manifest,
                    state: .cancelled,
                    failureReason: "cancelled",
                    generations: allGenerations,
                    candidates: allCandidates,
                    fitness: allFitness,
                    evaluationTraces: allEvaluationTraces,
                    bestFitness: bestAcceptedFitness,
                    artifactDirectory: artifactDirectory,
                    onEvent: onEvent
                )
            } catch {
                return await finish(
                    manifest: manifest,
                    state: .failed,
                    failureReason: "evolution-backend-failed: \(error)",
                    generations: allGenerations,
                    candidates: allCandidates,
                    fitness: allFitness,
                    evaluationTraces: allEvaluationTraces,
                    artifactDirectory: artifactDirectory,
                    onEvent: onEvent
                )
            }
        }
        let state: EvolutionRunTerminalState = bestAcceptedFitness == nil ? .rejected : .completed
        return await finish(
            manifest: manifest,
            state: state,
            failureReason: state == .completed ? nil : finalGateReport?.rejectionReasons.joined(separator: ","),
            generations: allGenerations,
            candidates: allCandidates,
            fitness: allFitness,
            evaluationTraces: allEvaluationTraces,
            bestFitness: bestAcceptedFitness,
            artifactDirectory: artifactDirectory,
            onEvent: onEvent
        )
    }

    private struct EvaluationBatch: Sendable {
        let fitness: [FitnessSummary]
        let traces: [EvolutionCandidateEvaluationTrace]
    }

    private func evaluate(
        config: EvolutionRunConfig,
        population: EvolutionPopulation,
        generationArtifactDirectory: URL,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)?
    ) async throws -> EvaluationBatch {
        if let batchEvaluator = evaluator as? any EvolutionCandidateBatchEvaluating,
           population.candidates.count > 1 {
            return try await evaluateWithBatchEvaluator(
                config: config,
                population: population,
                generationArtifactDirectory: generationArtifactDirectory,
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
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)?,
        batchEvaluator: any EvolutionCandidateBatchEvaluating
    ) async throws -> EvaluationBatch {
        var records: [FitnessSummary] = []
        var traces: [EvolutionCandidateEvaluationTrace] = []
        records.reserveCapacity(population.candidates.count)
        traces.reserveCapacity(population.candidates.count)
        let batchSize = max(1, min(config.candidateEvaluationConcurrency, population.candidates.count))
        let recorder = EvolutionEvaluationTraceRecorder()
        var nextIndex = 0
        while nextIndex < population.candidates.count {
            try Task.checkCancellation()
            let batchEnd = min(nextIndex + batchSize, population.candidates.count)
            let candidates = Array(population.candidates[nextIndex..<batchEnd])
            var starts: [String: (startedAt: Date, activeEvaluationCountAtStart: Int)] = [:]
            for candidate in candidates {
                starts[candidate.candidateID] = await recorder.begin()
            }
            let summaries = try await batchEvaluator.evaluateCandidates(request: EvolutionCandidateBatchEvaluationRequest(
                config: config,
                candidates: candidates,
                generationArtifactDirectory: generationArtifactDirectory,
                workerCount: config.workerCount
            ))
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
                let trace = await recorder.end(
                    runID: config.runID,
                    generationIndex: candidate.generationIndex,
                    candidateID: candidate.candidateID,
                    requestedConcurrency: batchSize,
                    started: starts[candidate.candidateID] ?? (
                        startedAt: Date(),
                        activeEvaluationCountAtStart: 1
                    )
                )
                records.append(summary)
                traces.append(trace)
            }
            nextIndex = batchEnd
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

    private func finish(
        manifest: EvolutionRunManifest,
        state: EvolutionRunTerminalState,
        failureReason: String?,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        evaluationTraces: [EvolutionCandidateEvaluationTrace] = [],
        bestFitness: FitnessSummary? = nil,
        artifactDirectory: URL,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)?
    ) async -> EvolutionRunResult {
        let eliteIDs = generations.flatMap(\.eliteCandidateIDs)
        let archive = EvolutionEliteArchive(
            runID: manifest.runID,
            eliteCandidateIDs: Array(Set(eliteIDs)).sorted(),
            bestCandidateID: bestFitness?.candidateID,
            bestFitness: bestFitness?.scalarFitness
        )
        let qualityDiversityArchive = EvolutionQualityDiversityArchiveBuilder()
            .build(runID: manifest.runID, fitness: fitness)
        let lineage = candidates.map { candidate in
            EvolutionLineageRecord(
                runID: candidate.runID,
                generationIndex: candidate.generationIndex,
                candidateID: candidate.candidateID,
                genomeID: candidate.genomeID,
                parentCandidateIDs: candidate.parentCandidateIDs
            )
        }
        let completedManifest = manifest.completed(
            at: Date(),
            terminalState: state,
            failureReason: failureReason
        )
        let result = EvolutionRunResult(
            manifest: completedManifest,
            generations: generations,
            candidates: candidates,
            fitness: fitness,
            eliteArchive: archive,
            qualityDiversityArchive: qualityDiversityArchive,
            lineage: lineage,
            evaluationTraces: evaluationTraces
        )
        do {
            try artifactWriter.write(
                manifest: completedManifest,
                generations: generations,
                candidates: candidates,
                fitness: fitness,
                eliteArchive: archive,
                qualityDiversityArchive: qualityDiversityArchive,
                lineage: lineage,
                evaluationTraces: evaluationTraces,
                to: artifactDirectory
            )
        } catch {
            let failedManifest = completedManifest.completed(
                at: Date(),
                terminalState: .failed,
                failureReason: "evolution-artifact-write-failed: \(error)"
            )
            let failedResult = EvolutionRunResult(
                manifest: failedManifest,
                generations: generations,
                candidates: candidates,
                fitness: fitness,
                eliteArchive: archive,
                qualityDiversityArchive: qualityDiversityArchive,
                lineage: lineage,
                evaluationTraces: evaluationTraces
            )
            onEvent?(.completed(failedResult))
            return failedResult
        }
        onEvent?(.completed(result))
        return result
    }

    private func bestFitnessSummary(
        current: FitnessSummary?,
        candidateFitness: [FitnessSummary]
    ) -> FitnessSummary? {
        candidateFitness.reduce(current) { currentBest, candidate in
            guard candidate.scalarFitness.isFinite else { return currentBest }
            guard let currentBest else { return candidate }
            if candidate.scalarFitness == currentBest.scalarFitness {
                return candidate.candidateID < currentBest.candidateID ? candidate : currentBest
            }
            return candidate.scalarFitness > currentBest.scalarFitness ? candidate : currentBest
        }
    }

    private func commonRandomSeed(config: EvolutionRunConfig, generationIndex: Int) -> UInt64 {
        config.commonRandomSeed &+ UInt64(max(0, generationIndex)) &* 1_099_511_628_211
    }

    private func nextMutationSchedule(
        config: EvolutionRunConfig,
        currentMutationRate: Double,
        currentMutationNoiseScale: Double,
        gateReport: EvolutionGateReport
    ) -> (mutationRate: Double, mutationNoiseScale: Double) {
        guard config.adaptiveMutation.enabled else {
            return (currentMutationRate, currentMutationNoiseScale)
        }
        let factor = shouldDecayMutation(gateReport: gateReport)
            ? config.adaptiveMutation.decayFactor
            : config.adaptiveMutation.increaseFactor
        let mutationRate = clamp(
            currentMutationRate * factor,
            min: config.adaptiveMutation.minimumMutationRate,
            max: config.adaptiveMutation.maximumMutationRate
        )
        let mutationNoiseScale = clamp(
            currentMutationNoiseScale * factor,
            min: config.adaptiveMutation.minimumNoiseScale,
            max: config.adaptiveMutation.maximumNoiseScale
        )
        return (mutationRate, mutationNoiseScale)
    }

    private func shouldDecayMutation(gateReport: EvolutionGateReport) -> Bool {
        guard gateReport.accepted else { return false }
        guard let bestVsIncumbentDelta = gateReport.bestVsIncumbentDelta else {
            return true
        }
        let minimumImprovement = gateReport.minimumImprovementOverIncumbent ?? 0
        return bestVsIncumbentDelta > minimumImprovement
    }

    private func incumbentImproved(gateReport: EvolutionGateReport) -> Bool {
        guard let bestVsIncumbentDelta = gateReport.bestVsIncumbentDelta else {
            return false
        }
        let minimumImprovement = gateReport.minimumImprovementOverIncumbent ?? 0
        return bestVsIncumbentDelta > minimumImprovement
    }

    private func evaluationFailureFitness(
        config: EvolutionRunConfig,
        candidates: [GenomeCandidate],
        error: any Error
    ) -> [FitnessSummary] {
        let reason = "evaluation-failed:\(String(describing: error))"
        let failedMetric = -1.0e12
        return candidates.map { candidate in
            FitnessSummary(
                runID: config.runID,
                generationIndex: candidate.generationIndex,
                candidateID: candidate.candidateID,
                taskID: config.taskID,
                scalarFitness: failedMetric,
                rewardAverage: failedMetric,
                taskPassRate: 0,
                safetyViolationRate: 1,
                holdTimeRatio: 0,
                altitudeErrorRatio: nil,
                energyPenalty: nil,
                noveltyScore: nil,
                teacherDelta: nil,
                workerThroughput: 0,
                behaviorDescriptor: [
                    "evaluation.failed": 1,
                ],
                failureReasons: [reason]
            )
        }
    }

    private func evaluationFailureTraces(
        config: EvolutionRunConfig,
        candidates: [GenomeCandidate]
    ) -> [EvolutionCandidateEvaluationTrace] {
        let completedAt = Date()
        let requestedConcurrency = max(1, min(config.candidateEvaluationConcurrency, candidates.count))
        return candidates.enumerated().map { offset, candidate in
            EvolutionCandidateEvaluationTrace(
                runID: config.runID,
                generationIndex: candidate.generationIndex,
                candidateID: candidate.candidateID,
                requestedConcurrency: requestedConcurrency,
                activeEvaluationCountAtStart: min(offset + 1, requestedConcurrency),
                startedAt: completedAt,
                completedAt: completedAt
            )
        }
    }

    private func evaluationCancellationFitness(
        config: EvolutionRunConfig,
        candidates: [GenomeCandidate]
    ) -> [FitnessSummary] {
        let cancelledMetric = -1.0e12
        return candidates.map { candidate in
            FitnessSummary(
                runID: config.runID,
                generationIndex: candidate.generationIndex,
                candidateID: candidate.candidateID,
                taskID: config.taskID,
                scalarFitness: cancelledMetric,
                rewardAverage: cancelledMetric,
                taskPassRate: 0,
                safetyViolationRate: 1,
                holdTimeRatio: 0,
                altitudeErrorRatio: nil,
                energyPenalty: nil,
                noveltyScore: nil,
                teacherDelta: nil,
                workerThroughput: 0,
                behaviorDescriptor: [
                    "evaluation.cancelled": 1,
                ],
                failureReasons: ["evaluation-cancelled"]
            )
        }
    }

    private func evaluationCancellationTraces(
        config: EvolutionRunConfig,
        candidates: [GenomeCandidate]
    ) -> [EvolutionCandidateEvaluationTrace] {
        let completedAt = Date()
        let requestedConcurrency = max(1, min(config.candidateEvaluationConcurrency, candidates.count))
        return candidates.map { candidate in
            EvolutionCandidateEvaluationTrace(
                runID: config.runID,
                generationIndex: candidate.generationIndex,
                candidateID: candidate.candidateID,
                requestedConcurrency: requestedConcurrency,
                activeEvaluationCountAtStart: 1,
                startedAt: completedAt,
                completedAt: completedAt
            )
        }
    }

    private func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}

private struct EvolutionEarlyStoppingState {
    private let config: EvolutionEarlyStoppingConfig
    private var bestFitness: Double?
    private var bestTaskPassRate: Double?
    private var bestHoldTimeRatio: Double?
    private var stagnantGenerationCount = 0

    init(config: EvolutionEarlyStoppingConfig) {
        self.config = config
    }

    mutating func record(fitness: [FitnessSummary]) -> String? {
        guard config.enabled, !fitness.isEmpty else {
            return nil
        }
        let generationBestFitness = fitness.compactMap { summary in
            summary.scalarFitness.isFinite ? summary.scalarFitness : nil
        }.max()
        let generationBestTaskPassRate = fitness.compactMap { summary in
            summary.taskPassRate.isFinite ? summary.taskPassRate : nil
        }.max()
        let generationBestHoldTimeRatio = fitness.compactMap { summary in
            summary.holdTimeRatio?.isFinite == true ? summary.holdTimeRatio : nil
        }.max()

        let improved = improved(
            current: generationBestFitness,
            best: bestFitness,
            minimumDelta: config.minimumFitnessImprovement
        ) || improved(
            current: generationBestTaskPassRate,
            best: bestTaskPassRate,
            minimumDelta: config.minimumTaskPassRateImprovement
        ) || improved(
            current: generationBestHoldTimeRatio,
            best: bestHoldTimeRatio,
            minimumDelta: config.minimumHoldTimeRatioImprovement
        )

        updateBest(&bestFitness, with: generationBestFitness)
        updateBest(&bestTaskPassRate, with: generationBestTaskPassRate)
        updateBest(&bestHoldTimeRatio, with: generationBestHoldTimeRatio)

        if improved {
            stagnantGenerationCount = 0
            return nil
        }
        stagnantGenerationCount += 1
        guard stagnantGenerationCount >= config.patienceGenerations else {
            return nil
        }
        return [
            "early-stopped:plateau",
            "stagnantGenerations=\(stagnantGenerationCount)",
            "patience=\(config.patienceGenerations)",
            bestFitness.map { "bestFitness=\($0)" },
            bestTaskPassRate.map { "bestTaskPassRate=\($0)" },
            bestHoldTimeRatio.map { "bestHoldTimeRatio=\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: ":")
    }

    private func improved(current: Double?, best: Double?, minimumDelta: Double) -> Bool {
        guard let current else {
            return false
        }
        guard let best else {
            return true
        }
        return current > best + minimumDelta
    }

    private func updateBest(_ best: inout Double?, with current: Double?) {
        guard let current else {
            return
        }
        guard let existing = best else {
            best = current
            return
        }
        if current > existing {
            best = current
        }
    }
}

private actor EvolutionEvaluationTraceRecorder {
    private var activeCount = 0

    func begin() -> (startedAt: Date, activeEvaluationCountAtStart: Int) {
        activeCount += 1
        return (Date(), activeCount)
    }

    func end(
        runID: String,
        generationIndex: Int,
        candidateID: String,
        requestedConcurrency: Int,
        started: (startedAt: Date, activeEvaluationCountAtStart: Int)
    ) -> EvolutionCandidateEvaluationTrace {
        let completedAt = Date()
        activeCount = max(0, activeCount - 1)
        return EvolutionCandidateEvaluationTrace(
            runID: runID,
            generationIndex: generationIndex,
            candidateID: candidateID,
            requestedConcurrency: requestedConcurrency,
            activeEvaluationCountAtStart: started.activeEvaluationCountAtStart,
            startedAt: started.startedAt,
            completedAt: completedAt
        )
    }
}
