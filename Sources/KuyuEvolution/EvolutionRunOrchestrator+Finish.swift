import Foundation
import KuyuTrainingContracts

extension EvolutionRunOrchestrator {
    func finish(
        manifest: EvolutionRunManifest,
        state: EvolutionRunTerminalState,
        failureReason: String?,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        evaluationTraces: [EvolutionCandidateEvaluationTrace] = [],
        acceptanceEvaluations: [EvolutionCandidateAcceptanceRecord] = [],
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
            evaluationTraces: evaluationTraces,
            acceptanceEvaluations: acceptanceEvaluations
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
                acceptanceEvaluations: acceptanceEvaluations,
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
                evaluationTraces: evaluationTraces,
                acceptanceEvaluations: acceptanceEvaluations
            )
            onEvent?(.completed(failedResult))
            return failedResult
        }
        onEvent?(.completed(result))
        return result
    }
}
