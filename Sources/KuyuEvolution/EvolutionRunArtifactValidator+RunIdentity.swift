import Foundation
import KuyuTrainingContracts

extension EvolutionRunArtifactValidator {
    func validateRunIDs(
        expected: String,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        eliteArchive: EvolutionEliteArchive,
        acceptedCheckpoint: EvolutionAcceptedCheckpointDecision,
        qualityDiversityArchive: EvolutionQualityDiversityArchive,
        lineage: [EvolutionLineageRecord],
        evaluationTraces: [EvolutionCandidateEvaluationTrace],
        acceptanceEvaluations: [EvolutionCandidateAcceptanceRecord]
    ) throws {
        if eliteArchive.runID != expected {
            throw ValidationError.runIDMismatch(file: "elite-archive.json", expected: expected, actual: eliteArchive.runID)
        }
        if qualityDiversityArchive.runID != expected {
            throw ValidationError.runIDMismatch(file: EvolutionQualityDiversityArchive.fileName, expected: expected, actual: qualityDiversityArchive.runID)
        }
        if acceptedCheckpoint.runID != expected {
            throw ValidationError.runIDMismatch(
                file: EvolutionAcceptedCheckpointDecision.fileName,
                expected: expected,
                actual: acceptedCheckpoint.runID
            )
        }
        for record in generations where record.runID != expected {
            throw ValidationError.runIDMismatch(file: "generations.jsonl", expected: expected, actual: record.runID)
        }
        for candidate in candidates where candidate.runID != expected {
            throw ValidationError.runIDMismatch(file: "candidates.jsonl", expected: expected, actual: candidate.runID)
        }
        for summary in fitness where summary.runID != expected {
            throw ValidationError.runIDMismatch(file: "fitness.jsonl", expected: expected, actual: summary.runID)
        }
        for record in lineage where record.runID != expected {
            throw ValidationError.runIDMismatch(file: "lineage.json", expected: expected, actual: record.runID)
        }
        for trace in evaluationTraces where trace.runID != expected {
            throw ValidationError.runIDMismatch(file: "evaluation-trace.jsonl", expected: expected, actual: trace.runID)
        }
        for record in acceptanceEvaluations where record.runID != expected {
            throw ValidationError.runIDMismatch(
                file: "acceptance-evaluations.jsonl",
                expected: expected,
                actual: record.runID
            )
        }
    }
}
