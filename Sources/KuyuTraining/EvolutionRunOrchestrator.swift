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

    public init(
        manifest: EvolutionRunManifest,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        eliteArchive: EvolutionEliteArchive,
        qualityDiversityArchive: EvolutionQualityDiversityArchive,
        lineage: [EvolutionLineageRecord]
    ) {
        self.manifest = manifest
        self.generations = generations
        self.candidates = candidates
        self.fitness = fitness
        self.eliteArchive = eliteArchive
        self.qualityDiversityArchive = qualityDiversityArchive
        self.lineage = lineage
    }
}

@MainActor
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

    public init(
        backend: any EvolutionaryTrainingBackend,
        evaluator: any EvolutionCandidateEvaluating,
        artifactWriter: any EvolutionArtifactWriting = EvolutionArtifactWriter(),
        parentSelectionPolicy: EvolutionParentSelectionPolicy = EvolutionParentSelectionPolicy()
    ) {
        self.backend = backend
        self.evaluator = evaluator
        self.artifactWriter = artifactWriter
        self.parentSelectionPolicy = parentSelectionPolicy
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
        var bestAcceptedFitness: FitnessSummary?
        var finalGateReport: EvolutionGateReport?
        var incumbentCandidateID: String?
        var incumbentFitness: Double?
        var mutationRate = config.mutationRate
        var mutationNoiseScale = config.mutationNoiseScale

        for generationIndex in 0..<config.generationCount {
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
                generationFitness = try await evaluate(
                    config: config,
                    population: currentPopulation,
                    generationArtifactDirectory: generationDirectory,
                    onEvent: onEvent
                )
            } catch {
                return await finish(
                    manifest: manifest,
                    state: .failed,
                    failureReason: "evolution-evaluation-failed: \(error)",
                    generations: allGenerations,
                    candidates: allCandidates,
                    fitness: allFitness,
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
            } catch {
                return await finish(
                    manifest: manifest,
                    state: .failed,
                    failureReason: "evolution-backend-failed: \(error)",
                    generations: allGenerations,
                    candidates: allCandidates,
                    fitness: allFitness,
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
            bestFitness: bestAcceptedFitness,
            artifactDirectory: artifactDirectory,
            onEvent: onEvent
        )
    }

    private func evaluate(
        config: EvolutionRunConfig,
        population: EvolutionPopulation,
        generationArtifactDirectory: URL,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)?
    ) async throws -> [FitnessSummary] {
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

    private func evaluateSequentially(
        config: EvolutionRunConfig,
        population: EvolutionPopulation,
        generationArtifactDirectory: URL,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)?
    ) async throws -> [FitnessSummary] {
        var records: [FitnessSummary] = []
        records.reserveCapacity(population.candidates.count)
        for candidate in population.candidates {
            let summary = try await evaluator.evaluateCandidate(request: EvolutionCandidateEvaluationRequest(
                config: config,
                candidate: candidate,
                generationArtifactDirectory: generationArtifactDirectory,
                workerCount: config.workerCount
            ))
            records.append(summary)
            onEvent?(.candidateEvaluated(summary))
        }
        return records
    }

    private func evaluateConcurrently(
        config: EvolutionRunConfig,
        population: EvolutionPopulation,
        generationArtifactDirectory: URL,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)?
    ) async throws -> [FitnessSummary] {
        var records = Array<FitnessSummary?>(repeating: nil, count: population.candidates.count)
        let evaluator = evaluator
        let concurrency = max(1, min(config.candidateEvaluationConcurrency, population.candidates.count))
        var nextIndex = 0
        while nextIndex < population.candidates.count {
            let batchEnd = min(nextIndex + concurrency, population.candidates.count)
            try await withThrowingTaskGroup(of: (Int, FitnessSummary).self) { group in
                for index in nextIndex..<batchEnd {
                    let candidate = population.candidates[index]
                    group.addTask {
                        let summary = try await evaluator.evaluateCandidate(request: EvolutionCandidateEvaluationRequest(
                            config: config,
                            candidate: candidate,
                            generationArtifactDirectory: generationArtifactDirectory,
                            workerCount: config.workerCount
                        ))
                        return (index, summary)
                    }
                }
                for try await (index, summary) in group {
                    records[index] = summary
                    onEvent?(.candidateEvaluated(summary))
                }
            }
            nextIndex = batchEnd
        }
        return records.compactMap { $0 }
    }

    private func finish(
        manifest: EvolutionRunManifest,
        state: EvolutionRunTerminalState,
        failureReason: String?,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
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
            lineage: lineage
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
                lineage: lineage
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
        let factor = gateReport.accepted
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

    private func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}
