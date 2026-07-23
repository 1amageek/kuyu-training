import Foundation
import KuyuTrainingContracts

extension EvolutionRunArtifactValidator {
    func validate(
        manifest: EvolutionRunManifest,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        eliteArchive: EvolutionEliteArchive,
        acceptedCheckpoint: EvolutionAcceptedCheckpointDecision,
        qualityDiversityArchive: EvolutionQualityDiversityArchive,
        lineage: [EvolutionLineageRecord],
        evaluationTraces: [EvolutionCandidateEvaluationTrace],
        acceptanceEvaluations: [EvolutionCandidateAcceptanceRecord],
        artifactDirectory: URL
    ) throws {
        guard !manifest.runID.isEmpty else {
            throw ValidationError.emptyRunID
        }
        guard manifest.terminalState != .running else {
            throw ValidationError.nonTerminalManifestState(manifest.terminalState)
        }
        try validateRunIDs(
            expected: manifest.runID,
            generations: generations,
            candidates: candidates,
            fitness: fitness,
            eliteArchive: eliteArchive,
            acceptedCheckpoint: acceptedCheckpoint,
            qualityDiversityArchive: qualityDiversityArchive,
            lineage: lineage,
            evaluationTraces: evaluationTraces,
            acceptanceEvaluations: acceptanceEvaluations
        )
        let candidateIDs = try validateCandidates(candidates)
        try validateFitness(fitness, candidates: candidates, manifest: manifest)
        try validateGenerations(generations)
        try validateLineage(lineage, candidates: candidates)
        try validateEliteArchive(
            eliteArchive,
            manifest: manifest,
            candidateIDs: candidateIDs,
            fitness: fitness
        )
        try validateAcceptedCheckpoint(
            acceptedCheckpoint,
            manifest: manifest,
            candidates: candidates,
            fitness: fitness,
            eliteArchive: eliteArchive,
            acceptanceEvaluations: acceptanceEvaluations,
            artifactDirectory: artifactDirectory
        )
        try validateQualityDiversityArchive(qualityDiversityArchive, candidateIDs: candidateIDs)
        try validateEvaluationTraces(
            evaluationTraces,
            manifest: manifest,
            candidateIDs: candidateIDs
        )
        try validateAcceptanceEvaluations(
            acceptanceEvaluations,
            manifest: manifest,
            generations: generations,
            candidates: candidates,
            eliteArchive: eliteArchive,
            artifactDirectory: artifactDirectory
        )
    }

    func validateCandidates(_ candidates: [GenomeCandidate]) throws -> Set<String> {
        var candidateIDs = Set<String>()
        var incumbentCandidateID: String?
        var carryoverGenerationIndices = Set<Int>()
        for candidate in candidates {
            guard candidateIDs.insert(candidate.candidateID).inserted else {
                throw ValidationError.duplicateCandidateID(candidate.candidateID)
            }
            if candidate.isIncumbent == true {
                guard incumbentCandidateID == nil else {
                    throw ValidationError.duplicateIncumbentCandidate(candidate.candidateID)
                }
                guard candidate.generationIndex == 0,
                      candidate.parentCandidateIDs.isEmpty,
                      candidate.mutationRate == 0,
                      candidate.mutationNoiseScale == 0 else {
                    throw ValidationError.invalidIncumbentCandidate(candidate.candidateID)
                }
                incumbentCandidateID = candidate.candidateID
            }
            if candidate.isCarryover == true {
                guard carryoverGenerationIndices.insert(candidate.generationIndex).inserted else {
                    throw ValidationError.duplicateCarryoverCandidate(
                        generationIndex: candidate.generationIndex,
                        candidateID: candidate.candidateID
                    )
                }
                guard candidate.mutationRate == 0,
                      candidate.mutationNoiseScale == 0 else {
                    throw ValidationError.invalidCarryoverCandidate(candidate.candidateID)
                }
            }
        }
        return candidateIDs
    }

    func validateFitness(
        _ fitness: [FitnessSummary],
        candidates: [GenomeCandidate],
        manifest: EvolutionRunManifest
    ) throws {
        var fitnessByCandidateID: [String: FitnessSummary] = [:]
        var allowedFidelities = [manifest.searchEvaluationFidelity]
        if let refinementFidelity = manifest.searchRefinementPolicy?.evaluationFidelity {
            allowedFidelities.append(refinementFidelity)
        }
        for summary in fitness {
            guard fitnessByCandidateID[summary.candidateID] == nil else {
                throw ValidationError.duplicateFitnessSummary(summary.candidateID)
            }
            fitnessByCandidateID[summary.candidateID] = summary
            guard allowedFidelities.contains(summary.evaluationFidelity) else {
                throw ValidationError.unexpectedFitnessFidelity(candidateID: summary.candidateID)
            }
            if !summary.evaluationFidelity.isFullScenario,
               (manifest.terminalState == .completed || manifest.terminalState == .rejected),
               !summary.failureReasons.contains("search-refinement-not-selected") {
                throw ValidationError.screeningFitnessMissingRejection(
                    candidateID: summary.candidateID
                )
            }
        }
        for candidate in candidates {
            guard let summary = fitnessByCandidateID[candidate.candidateID] else {
                throw ValidationError.missingCandidateFitness(candidate.candidateID)
            }
            guard summary.scalarFitness.isFinite,
                  summary.rewardAverage.isFinite,
                  summary.taskPassRate.isFinite,
                  summary.safetyViolationRate.isFinite,
                  summary.holdTimeRatio?.isFinite ?? true,
                  summary.altitudeErrorRatio?.isFinite ?? true,
                  summary.energyPenalty?.isFinite ?? true,
                  summary.noveltyScore?.isFinite ?? true,
                  summary.teacherDelta?.isFinite ?? true,
                  summary.workerThroughput?.isFinite ?? true else {
                throw ValidationError.nonFiniteFitness(candidateID: candidate.candidateID)
            }
        }
    }

    func validateGenerations(_ generations: [PopulationGenerationRecord]) throws {
        for record in generations {
            let expectedImproved: Bool
            if let bestVsIncumbentDelta = record.bestVsIncumbentDelta {
                expectedImproved = bestVsIncumbentDelta > (record.minimumImprovementOverIncumbent ?? 0)
            } else {
                expectedImproved = false
            }
            guard record.incumbentImproved == expectedImproved else {
                throw ValidationError.generationImprovementMismatch(record.generationIndex)
            }
        }
    }

    func validateLineage(_ lineage: [EvolutionLineageRecord], candidates: [GenomeCandidate]) throws {
        var lineageByCandidateID: [String: EvolutionLineageRecord] = [:]
        for record in lineage {
            guard lineageByCandidateID[record.candidateID] == nil else {
                throw ValidationError.duplicateLineage(record.candidateID)
            }
            lineageByCandidateID[record.candidateID] = record
        }
        for candidate in candidates {
            guard let record = lineageByCandidateID[candidate.candidateID],
                  record.genomeID == candidate.genomeID,
                  record.parentCandidateIDs == candidate.parentCandidateIDs else {
                throw ValidationError.lineageMismatch(candidateID: candidate.candidateID)
            }
        }
    }

    func validateQualityDiversityArchive(
        _ archive: EvolutionQualityDiversityArchive,
        candidateIDs: Set<String>
    ) throws {
        for cell in archive.cells {
            guard candidateIDs.contains(cell.candidateID) else {
                throw ValidationError.qualityDiversityCandidateMissing(cell.candidateID)
            }
            guard cell.fitness.isFinite,
                  cell.behaviorDescriptor.values.allSatisfy(\.isFinite) else {
                throw ValidationError.nonFiniteQualityDiversityCell(cell.cellID)
            }
        }
    }
}
