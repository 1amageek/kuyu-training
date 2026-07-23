import KuyuTrainingContracts

extension EvolutionRunArtifactValidator {
    func validateEliteArchive(
        _ eliteArchive: EvolutionEliteArchive,
        manifest: EvolutionRunManifest,
        candidateIDs: Set<String>,
        fitness: [FitnessSummary]
    ) throws {
        for candidateID in eliteArchive.eliteCandidateIDs {
            guard candidateIDs.contains(candidateID) else {
                throw ValidationError.eliteCandidateMissing(candidateID)
            }
        }
        if manifest.terminalState == .completed {
            guard !eliteArchive.eliteCandidateIDs.isEmpty,
                  eliteArchive.bestCandidateID != nil,
                  eliteArchive.bestFitness != nil else {
                throw ValidationError.missingCompletedEliteArchive
            }
        }
        if let bestCandidateID = eliteArchive.bestCandidateID {
            guard candidateIDs.contains(bestCandidateID) else {
                throw ValidationError.bestCandidateMissing(bestCandidateID)
            }
            guard eliteArchive.eliteCandidateIDs.contains(bestCandidateID) else {
                throw ValidationError.bestCandidateNotElite(bestCandidateID)
            }
            let evaluatedSummary = fitness.first {
                $0.candidateID == bestCandidateID
            }
            guard evaluatedSummary?.evaluationFidelity.isFullScenario == true else {
                throw ValidationError.bestCandidateNotFullScenario(bestCandidateID)
            }
            let evaluatedFitness = evaluatedSummary?.scalarFitness
            guard eliteArchive.bestFitness == evaluatedFitness else {
                throw ValidationError.bestFitnessMismatch(
                    candidateID: bestCandidateID,
                    archived: eliteArchive.bestFitness,
                    evaluated: evaluatedFitness
                )
            }
        } else if eliteArchive.bestFitness != nil {
            throw ValidationError.bestFitnessMismatch(
                candidateID: "nil",
                archived: eliteArchive.bestFitness,
                evaluated: nil
            )
        }
    }
}
