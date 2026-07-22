import Foundation
import KuyuTrainingContracts

extension EvolutionRunArtifactValidator {
    func validateAcceptanceEvaluations(
        _ records: [EvolutionCandidateAcceptanceRecord],
        manifest: EvolutionRunManifest,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        eliteArchive: EvolutionEliteArchive,
        artifactDirectory: URL
    ) throws {
        switch manifest.candidateAcceptanceMode {
        case .searchGateOnly:
            guard records.isEmpty else {
                throw ValidationError.acceptanceModeMismatch("search-gate-only-has-dedicated-records")
            }
        case .dedicatedEvaluation, .dedicatedAbsoluteThreshold:
            break
        }

        var keys = Set<String>()
        for record in records {
            let key = "\(record.generationIndex)/\(record.candidateID)"
            guard keys.insert(key).inserted else {
                throw ValidationError.duplicateAcceptanceEvaluation(
                    generationIndex: record.generationIndex,
                    candidateID: record.candidateID
                )
            }
            guard let candidate = candidates.first(where: { $0.candidateID == record.candidateID }) else {
                throw ValidationError.acceptanceCandidateMissing(record.candidateID)
            }
            guard candidate.generationIndex == record.generationIndex,
                  record.fitness.runID == record.runID,
                  record.fitness.generationIndex == record.generationIndex,
                  record.fitness.candidateID == record.candidateID,
                  record.fitness.taskID == manifest.taskID,
                  record.accepted == record.rejectionReasons.isEmpty else {
                throw ValidationError.acceptanceIdentityMismatch(record.candidateID)
            }
            guard let incumbentCandidate = candidates.first(where: {
                $0.candidateID == record.incumbentCandidateID
            }),
                  incumbentCandidate.isIncumbent == true,
                  record.incumbentFitness.runID == record.runID,
                  record.incumbentFitness.generationIndex == incumbentCandidate.generationIndex,
                  record.incumbentFitness.candidateID == incumbentCandidate.candidateID,
                  record.incumbentFitness.taskID == manifest.taskID else {
                throw ValidationError.acceptanceIdentityMismatch(record.candidateID)
            }
            guard let checkpointID = candidate.checkpointID,
                  let checkpointURL = candidate.checkpointURL,
                  record.checkpointReference.checkpointID == checkpointID,
                  record.checkpointReference.checkpointURL.standardizedFileURL == checkpointURL.standardizedFileURL else {
                throw ValidationError.acceptanceIdentityMismatch(record.candidateID)
            }
            do {
                try EvolutionCheckpointIntegrity().validate(
                    record.checkpointReference,
                    expectedCheckpointID: checkpointID,
                    expectedCheckpointURL: checkpointURL,
                    artifactRoot: artifactDirectory
                )
            } catch {
                throw ValidationError.invalidCheckpointReference(
                    candidateID: record.candidateID,
                    reason: String(describing: error)
                )
            }
            guard let incumbentCheckpointID = incumbentCandidate.checkpointID,
                  let incumbentCheckpointURL = incumbentCandidate.checkpointURL,
                  record.incumbentCheckpointReference.checkpointID == incumbentCheckpointID,
                  record.incumbentCheckpointReference.checkpointURL.standardizedFileURL
                    == incumbentCheckpointURL.standardizedFileURL else {
                throw ValidationError.acceptanceIdentityMismatch(record.candidateID)
            }
            do {
                try EvolutionCheckpointIntegrity().validate(
                    record.incumbentCheckpointReference,
                    expectedCheckpointID: incumbentCheckpointID,
                    expectedCheckpointURL: incumbentCheckpointURL,
                    artifactRoot: artifactDirectory
                )
            } catch {
                throw ValidationError.invalidCheckpointReference(
                    candidateID: record.incumbentCandidateID,
                    reason: String(describing: error)
                )
            }
            guard [record.fitness, record.incumbentFitness].allSatisfy({ summary in
                summary.scalarFitness.isFinite
                    && summary.rewardAverage.isFinite
                    && summary.taskPassRate.isFinite
                    && summary.safetyViolationRate.isFinite
                    && (summary.holdTimeRatio?.isFinite ?? true)
                    && (summary.altitudeErrorRatio?.isFinite ?? true)
                    && (summary.energyPenalty?.isFinite ?? true)
                    && (summary.noveltyScore?.isFinite ?? true)
                    && (summary.teacherDelta?.isFinite ?? true)
                    && (summary.workerThroughput?.isFinite ?? true)
                    && summary.behaviorDescriptor.values.allSatisfy(\.isFinite)
            }) else {
                throw ValidationError.nonFiniteAcceptanceFitness(record.candidateID)
            }
            let result = EvolutionCandidateAcceptanceResult(
                fitness: record.fitness,
                incumbentFitness: record.incumbentFitness,
                evaluationContract: record.evaluationContract,
                evidence: record.evidence
            )
            do {
                try EvolutionCandidateAcceptanceResultValidator().validate(
                    result,
                    acceptanceDirectory: artifactDirectory.appendingPathComponent("acceptance", isDirectory: true)
                )
            } catch let error as EvolutionCandidateAcceptanceResultValidator.ValidationError {
                throw ValidationError.invalidAcceptanceContract(
                    candidateID: record.candidateID,
                    reason: String(describing: error)
                )
            } catch let error as EvolutionAcceptanceEvidenceIntegrity.IntegrityError {
                throw ValidationError.invalidAcceptanceEvidence(
                    candidateID: record.candidateID,
                    reason: String(describing: error)
                )
            }
        }

        guard manifest.candidateAcceptanceMode == .dedicatedEvaluation else { return }
        guard records.count <= 1 else {
            throw ValidationError.acceptanceModeMismatch("dedicated-evaluation-requires-one-final-record")
        }
        if let record = records.first,
           record.candidateID != eliteArchive.bestCandidateID {
            throw ValidationError.acceptanceModeMismatch("final-record-does-not-match-search-winner")
        }
        switch manifest.terminalState {
        case .completed:
            guard let bestCandidateID = eliteArchive.bestCandidateID,
                  records.count == 1,
                  records.first?.candidateID == bestCandidateID,
                  records.first?.accepted == true else {
                throw ValidationError.acceptanceModeMismatch("completed-run-missing-accepted-evaluation")
            }
        case .rejected:
            if eliteArchive.bestCandidateID != nil {
                guard records.count == 1, records.first?.accepted == false else {
                    throw ValidationError.acceptanceModeMismatch("rejected-search-winner-missing-final-evaluation")
                }
            } else if !records.isEmpty {
                throw ValidationError.acceptanceModeMismatch("search-rejected-run-has-final-evaluation")
            }
        case .running, .failed, .cancelled, .paused:
            break
        }
    }
}
