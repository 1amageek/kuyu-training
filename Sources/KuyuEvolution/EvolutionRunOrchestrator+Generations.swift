import Foundation
import KuyuTrainingContracts

extension EvolutionRunOrchestrator {
    func trailingRejectedGenerationCount(_ records: [PopulationGenerationRecord]) -> Int {
        var count = 0
        for record in records.reversed() {
            guard !record.accepted else { break }
            count += 1
        }
        return count
    }

    func runGenerations(
        manifest: EvolutionRunManifest,
        config: EvolutionRunConfig,
        initialPopulation: EvolutionPopulation,
        gatePolicy: EvolutionGatePolicy,
        artifactDirectory: URL,
        resume: EvolutionResumeState?,
        checkpointStore: EvolutionResumeCheckpointStore,
        stopRequested: @Sendable () -> Bool,
        progressReporter: (any TrainingProgressReporting)?,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)?
    ) async -> EvolutionRunResult {
        var currentPopulation = resume?.currentPopulation ?? initialPopulation
        var allGenerations = resume?.generations ?? []
        var allCandidates = resume?.candidates ?? []
        var allFitness = resume?.fitness ?? []
        var allEvaluationTraces = resume?.evaluationTraces ?? []
        let allAcceptanceEvaluations: [EvolutionCandidateAcceptanceRecord] = []
        var bestSearchFitness = resume?.bestSearchFitness ?? nil
        var finalGateReport: EvolutionGateReport?
        var incumbentCandidateID = resume?.incumbentCandidateID ?? nil
        var incumbentFitness = resume?.incumbentFitness ?? nil
        var mutationRate = resume?.mutationRate ?? config.mutationRate
        var mutationNoiseScale = resume?.mutationNoiseScale ?? config.mutationNoiseScale
        var earlyStoppingState = resume.map {
            EvolutionEarlyStoppingState(config: config.earlyStopping, snapshot: $0.earlyStopping)
        } ?? EvolutionEarlyStoppingState(config: config.earlyStopping)
        let startGenerationIndex = resume?.startGenerationIndex ?? 0
        let rejectedContinuationBudget = max(0, config.maxConsecutiveRejectedGenerations ?? 0)
        // Derived from the trailing records instead of persisted state so the
        // budget survives pause/resume without a checkpoint schema change.
        var consecutiveRejectedGenerations = trailingRejectedGenerationCount(
            resume?.generations ?? []
        )

        for generationIndex in startGenerationIndex..<config.generationCount {
            if Task.isCancelled {
                return await finish(
                    manifest: manifest,
                    state: .cancelled,
                    failureReason: "cancelled",
                    generations: allGenerations,
                    candidates: allCandidates,
                    fitness: allFitness,
                    evaluationTraces: allEvaluationTraces,
                    acceptanceEvaluations: allAcceptanceEvaluations,
                    bestFitness: bestSearchFitness,
                    artifactDirectory: artifactDirectory,
                    onEvent: onEvent
                )
            }
            if stopRequested() {
                // Cooperative graceful stop: the previous generation's checkpoint
                // is already durable, so this run is resumable from there.
                return await finish(
                    manifest: manifest,
                    state: .paused,
                    failureReason: "paused-at-generation-\(generationIndex)",
                    generations: allGenerations,
                    candidates: allCandidates,
                    fitness: allFitness,
                    evaluationTraces: allEvaluationTraces,
                    acceptanceEvaluations: allAcceptanceEvaluations,
                    bestFitness: bestSearchFitness,
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
                    acceptanceEvaluations: allAcceptanceEvaluations,
                    artifactDirectory: artifactDirectory,
                    onEvent: onEvent
                )
            }
            let generationDirectory = artifactDirectory
                .appendingPathComponent("generations", isDirectory: true)
                .appendingPathComponent("generation-\(generationIndex)", isDirectory: true)
            // Population evaluated this generation, captured before
            // produceNextGeneration reassigns currentPopulation, for the checkpoint.
            let evaluatedPopulation = currentPopulation
            allCandidates.append(contentsOf: currentPopulation.candidates)
            let generationFitness: [FitnessSummary]
            var generationTraces: [EvolutionCandidateEvaluationTrace] = []
            do {
                let evaluation = try await evaluate(
                    config: config,
                    population: currentPopulation,
                    generationArtifactDirectory: generationDirectory,
                    progressReporter: progressReporter,
                    onEvent: onEvent
                )
                generationFitness = noveltyScoringPolicy.score(
                    currentGeneration: evaluation.fitness,
                    archive: allFitness
                )
                generationTraces = evaluation.traces
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
                    acceptanceEvaluations: allAcceptanceEvaluations,
                    bestFitness: bestSearchFitness,
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
                    acceptanceEvaluations: allAcceptanceEvaluations,
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
            let searchGateReport = gatePolicy.report(
                runID: config.runID,
                generationIndex: generationIndex,
                fitness: generationFitness,
                incumbentCandidateID: incumbentCandidateID,
                incumbentFitness: incumbentFitness
            )
            let gateEligibleFitness = generationFitness.filter(gatePolicy.candidatePasses)
            finalGateReport = searchGateReport
            if searchGateReport.accepted,
               let searchWinnerID = searchGateReport.eliteCandidateIDs.first {
                bestSearchFitness = bestFitnessSummary(
                    current: bestSearchFitness,
                    candidateFitness: generationFitness.filter { $0.candidateID == searchWinnerID }
                )
            }
            let generationRecord = generationRecord(
                config: config,
                generationIndex: generationIndex,
                population: currentPopulation,
                generationFitness: generationFitness,
                allFitness: allFitness,
                gateReport: searchGateReport,
                mutationRate: mutationRate,
                mutationNoiseScale: mutationNoiseScale
            )
            allGenerations.append(generationRecord)
            onEvent?(.generationCompleted(generationRecord))
            let stopReason: String?
            if searchGateReport.accepted {
                consecutiveRejectedGenerations = 0
                stopReason = earlyStoppingState.record(fitness: gateEligibleFitness)
            } else {
                consecutiveRejectedGenerations += 1
                // Exploration below the gate: continue with ranking-selected
                // parents while the rejected-generation budget lasts.
                stopReason = consecutiveRejectedGenerations > rejectedContinuationBudget
                    ? "search-gate-rejected:generation=\(generationIndex)"
                    : nil
            }
            if let stopReason,
               generationIndex < config.generationCount - 1 {
                return await finishSearch(
                    manifest: manifest,
                    config: config,
                    searchFailureReason: stopReason,
                    generations: allGenerations,
                    candidates: allCandidates,
                    fitness: allFitness,
                    evaluationTraces: allEvaluationTraces,
                    restoredAcceptanceEvaluations: allAcceptanceEvaluations,
                    bestSearchFitness: bestSearchFitness,
                    artifactDirectory: artifactDirectory,
                    progressReporter: progressReporter,
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
                gateReport: searchGateReport
            )
            mutationRate = nextSchedule.mutationRate
            mutationNoiseScale = nextSchedule.mutationNoiseScale
            var parentCandidateIDs = parentSelectionPolicy.parentCandidateIDs(
                config: config,
                eliteCandidateIDs: searchGateReport.eliteCandidateIDs,
                generationFitness: allFitness.filter(gatePolicy.candidatePasses)
            )
            if parentCandidateIDs.isEmpty, !searchGateReport.accepted {
                // No gate-passing candidate exists; the run is inside its
                // rejected-generation budget. Exploration parents carry no
                // elite/QD/promotion eligibility.
                parentCandidateIDs = EvolutionSearchContinuationPolicy().explorationParentIDs(
                    fitness: generationFitness,
                    limit: config.eliteCount
                )
            }
            let candidatesByID = Dictionary(
                allCandidates.map { ($0.candidateID, $0) },
                uniquingKeysWith: { existing, _ in existing }
            )
            let parentCandidates = parentCandidateIDs.compactMap { candidatesByID[$0] }
            do {
                try Task.checkCancellation()
                currentPopulation = try await backend.produceNextGeneration(request: EvolutionGenerationRequest(
                    config: config,
                    previousPopulation: currentPopulation,
                    fitness: generationFitness,
                    eliteCandidateIDs: searchGateReport.eliteCandidateIDs,
                    parentCandidateIDs: parentCandidateIDs,
                    parentCandidates: parentCandidates,
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
                    acceptanceEvaluations: allAcceptanceEvaluations,
                    bestFitness: bestSearchFitness,
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
                    acceptanceEvaluations: allAcceptanceEvaluations,
                    artifactDirectory: artifactDirectory,
                    onEvent: onEvent
                )
            }
            // Commit point: generation `generationIndex` is fully evaluated and the
            // next population is produced. Persisting atomically here makes the run
            // resumable from generationIndex+1 after any interruption.
            let retentionRequest = EvolutionCandidateArtifactRetentionRequest(
                runID: config.runID,
                generationIndex: generationIndex,
                artifactDirectory: artifactDirectory,
                candidates: allCandidates,
                nextPopulation: currentPopulation,
                bestCandidateID: bestSearchFitness?.candidateID,
                incumbentCandidateID: incumbentCandidateID,
                protectedCandidateIDs: qualityDiversityCandidateIDs(
                    config: config,
                    fitness: allFitness.filter(gatePolicy.candidatePasses)
                )
            )
            do {
                try candidateArtifactRetainer.validate(retentionRequest)
            } catch {
                return await finish(
                    manifest: manifest,
                    state: .failed,
                    failureReason: "candidate-artifact-retention-live-set-invalid: \(error)",
                    generations: allGenerations,
                    candidates: allCandidates,
                    fitness: allFitness,
                    evaluationTraces: allEvaluationTraces,
                    acceptanceEvaluations: allAcceptanceEvaluations,
                    bestFitness: bestSearchFitness,
                    artifactDirectory: artifactDirectory,
                    onEvent: onEvent
                )
            }
            do {
                try checkpointStore.write(
                    EvolutionGenerationCheckpoint(
                        runID: config.runID,
                        configHash: config.configHash,
                        candidateAcceptanceMode: manifest.candidateAcceptanceMode,
                        lastCommittedGeneration: generationIndex,
                        generationRecord: generationRecord,
                        generationCandidates: evaluatedPopulation.candidates,
                        generationFitness: generationFitness,
                        generationTraces: generationTraces,
                        nextPopulation: currentPopulation,
                        mutationRate: mutationRate,
                        mutationNoiseScale: mutationNoiseScale,
                        earlyStopping: earlyStoppingState.snapshot,
                        incumbentCandidateID: incumbentCandidateID,
                        incumbentFitness: incumbentFitness,
                        bestSearchFitness: bestSearchFitness
                    ),
                    to: artifactDirectory
                )
            } catch {
                return await finish(
                    manifest: manifest,
                    state: .failed,
                    failureReason: "resume-checkpoint-write-failed: \(error)",
                    generations: allGenerations,
                    candidates: allCandidates,
                    fitness: allFitness,
                    evaluationTraces: allEvaluationTraces,
                    acceptanceEvaluations: allAcceptanceEvaluations,
                    bestFitness: bestSearchFitness,
                    artifactDirectory: artifactDirectory,
                    onEvent: onEvent
                )
            }
            do {
                try candidateArtifactRetainer.retain(retentionRequest)
            } catch {
                return await finish(
                    manifest: manifest,
                    state: .failed,
                    failureReason: "candidate-artifact-retention-failed: \(error)",
                    generations: allGenerations,
                    candidates: allCandidates,
                    fitness: allFitness,
                    evaluationTraces: allEvaluationTraces,
                    acceptanceEvaluations: allAcceptanceEvaluations,
                    bestFitness: bestSearchFitness,
                    artifactDirectory: artifactDirectory,
                    onEvent: onEvent
                )
            }
        }
        return await finishSearch(
            manifest: manifest,
            config: config,
            searchFailureReason: bestSearchFitness == nil
                ? finalGateReport?.rejectionReasons.joined(separator: ",")
                : nil,
            generations: allGenerations,
            candidates: allCandidates,
            fitness: allFitness,
            evaluationTraces: allEvaluationTraces,
            restoredAcceptanceEvaluations: allAcceptanceEvaluations,
            bestSearchFitness: bestSearchFitness,
            artifactDirectory: artifactDirectory,
            progressReporter: progressReporter,
            onEvent: onEvent
        )
    }
}
