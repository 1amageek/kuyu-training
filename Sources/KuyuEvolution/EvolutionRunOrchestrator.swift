import Foundation
import KuyuTrainingContracts

public struct EvolutionRunOrchestrator {
    public enum RunError: Error, Sendable, Equatable {
        case emptyPopulation(Int)
        case backendFailed(String)
        case evaluationFailed(String)
        case acceptanceFailed(String)
        case artifactWriteFailed(String)
    }

    public let backend: any EvolutionaryTrainingBackend
    public let evaluator: any EvolutionCandidateEvaluating
    public let candidateAcceptanceStage: EvolutionCandidateAcceptanceStage?
    public let artifactWriter: any EvolutionArtifactWriting
    public let parentSelectionPolicy: EvolutionParentSelectionPolicy
    public let noveltyScoringPolicy: EvolutionNoveltyScoringPolicy
    public let candidateArtifactRetainer: any EvolutionCandidateArtifactRetaining

    public init(
        backend: any EvolutionaryTrainingBackend,
        evaluator: any EvolutionCandidateEvaluating,
        candidateAcceptanceStage: EvolutionCandidateAcceptanceStage? = nil,
        artifactWriter: any EvolutionArtifactWriting = EvolutionArtifactWriter(),
        parentSelectionPolicy: EvolutionParentSelectionPolicy = EvolutionParentSelectionPolicy(),
        noveltyScoringPolicy: EvolutionNoveltyScoringPolicy = EvolutionNoveltyScoringPolicy(),
        candidateArtifactRetainer: any EvolutionCandidateArtifactRetaining =
            EvolutionFullCandidateArtifactRetainer()
    ) {
        self.backend = backend
        self.evaluator = evaluator
        self.candidateAcceptanceStage = candidateAcceptanceStage
        self.artifactWriter = artifactWriter
        self.parentSelectionPolicy = parentSelectionPolicy
        self.noveltyScoringPolicy = noveltyScoringPolicy
        self.candidateArtifactRetainer = candidateArtifactRetainer
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
            candidateAcceptanceStage: nil,
            artifactWriter: artifactWriter,
            parentSelectionPolicy: parentSelectionPolicy,
            noveltyScoringPolicy: noveltyScoringPolicy,
            candidateArtifactRetainer: EvolutionFullCandidateArtifactRetainer()
        )
    }

    public func run(
        config: EvolutionRunConfig,
        gatePolicy: EvolutionGatePolicy? = nil,
        artifactDirectory: URL,
        resumeFrom: EvolutionResumeState? = nil,
        stopRequested: @escaping @Sendable () -> Bool = { false },
        progressReporter: (any TrainingProgressReporting)? = nil,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)? = nil
    ) async -> EvolutionRunResult {
        let manifest = initialManifest(config: config)
        onEvent?(.started(manifest))
        do {
            try EvolutionRunConfigValidator().validate(config)
        } catch {
            return await finish(
                manifest: manifest,
                state: .failed,
                failureReason: "invalid-evolution-config: \(error)",
                generations: [],
                candidates: [],
                fitness: [],
                artifactDirectory: artifactDirectory,
                onEvent: onEvent
            )
        }
        let checkpointStore = EvolutionResumeCheckpointStore()
        if let resumeFrom, resumeFrom.runID != config.runID {
            // Fail-closed: resuming under a different runID would write a mixed-runID
            // artifact set that the validator rejects. The caller must pass a config
            // whose runID matches the checkpoint.
            return await finish(
                manifest: manifest,
                state: .failed,
                failureReason: "resume-run-id-mismatch: config=\(config.runID) checkpoint=\(resumeFrom.runID)",
                generations: [],
                candidates: [],
                fitness: [],
                artifactDirectory: artifactDirectory,
                onEvent: onEvent
            )
        }
        if let resumeFrom,
           resumeFrom.candidateAcceptanceMode != manifest.candidateAcceptanceMode {
            return await finish(
                manifest: manifest,
                state: .failed,
                failureReason: "resume-acceptance-mode-mismatch: config=\(manifest.candidateAcceptanceMode.rawValue) checkpoint=\(resumeFrom.candidateAcceptanceMode.rawValue)",
                generations: [],
                candidates: [],
                fitness: [],
                artifactDirectory: artifactDirectory,
                onEvent: onEvent
            )
        }
        let resolvedGatePolicy = gatePolicy ?? EvolutionGatePolicy(eliteCount: config.eliteCount)
        do {
            try prepareCandidateArtifactRetention(
                config: config,
                gatePolicy: resolvedGatePolicy,
                artifactDirectory: artifactDirectory,
                expectedRunID: config.runID,
                resume: resumeFrom
            )
        } catch {
            return await finish(
                manifest: manifest,
                state: .failed,
                failureReason: String(describing: error),
                generations: resumeFrom?.generations ?? [],
                candidates: resumeFrom?.candidates ?? [],
                fitness: resumeFrom?.fitness ?? [],
                evaluationTraces: resumeFrom?.evaluationTraces ?? [],
                artifactDirectory: artifactDirectory,
                onEvent: onEvent
            )
        }
        do {
            try Task.checkCancellation()
            let initialPopulation: EvolutionPopulation
            if let resumeFrom {
                // Resume in place: skip re-seeding; the population to evaluate at
                // startGenerationIndex was produced before the interruption.
                initialPopulation = resumeFrom.currentPopulation
            } else {
                let seededPopulation = try await backend.seedPopulation(request: EvolutionSeedRequest(
                    config: config,
                    artifactDirectory: artifactDirectory,
                    mutationRate: config.mutationRate,
                    mutationNoiseScale: config.mutationNoiseScale,
                    commonRandomSeed: commonRandomSeed(config: config, generationIndex: 0)
                ))
                onEvent?(.populationSeeded(seededPopulation))
                initialPopulation = seededPopulation
            }
            return await runGenerations(
                manifest: manifest,
                config: config,
                initialPopulation: initialPopulation,
                gatePolicy: resolvedGatePolicy,
                artifactDirectory: artifactDirectory,
                resume: resumeFrom,
                checkpointStore: checkpointStore,
                stopRequested: stopRequested,
                progressReporter: progressReporter,
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
}
