import Foundation
import KuyuTrainingContracts

private func zipOptional<A, B>(_ lhs: A?, _ rhs: B?) -> (A, B)? {
    guard let lhs, let rhs else { return nil }
    return (lhs, rhs)
}

extension EvolutionRunArtifactValidator {
    func validateAcceptedCheckpoint(
        _ decision: EvolutionAcceptedCheckpointDecision,
        manifest: EvolutionRunManifest,
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        eliteArchive: EvolutionEliteArchive,
        acceptanceEvaluations: [EvolutionCandidateAcceptanceRecord],
        artifactDirectory: URL
    ) throws {
        guard decision.terminalState == manifest.terminalState else {
            throw ValidationError.acceptedCheckpointMismatch("terminal-state")
        }
        let improvementAccepted: Bool
        switch manifest.candidateAcceptanceMode {
        case .searchGateOnly:
            if let minimumImprovement = decision.minimumImprovementOverIncumbent,
               let incumbentFitness = decision.incumbentFitness,
               let bestFitness = eliteArchive.bestFitness {
                improvementAccepted = bestFitness > incumbentFitness + minimumImprovement
            } else {
                improvementAccepted = true
            }
        case .dedicatedEvaluation, .dedicatedAbsoluteThreshold:
            improvementAccepted = true
        }
        let candidateAcceptanceSatisfied: Bool
        switch manifest.candidateAcceptanceMode {
        case .searchGateOnly:
            candidateAcceptanceSatisfied = false
        case .dedicatedEvaluation, .dedicatedAbsoluteThreshold:
            candidateAcceptanceSatisfied = eliteArchive.bestCandidateID.map { candidateID in
                acceptanceEvaluations.contains { record in
                    record.candidateID == candidateID && record.accepted
                }
            } ?? false
        }
        let expectedAccepted = manifest.terminalState == .completed
            && eliteArchive.bestCandidateID != nil
            && improvementAccepted
            && candidateAcceptanceSatisfied
            && decision.publishMetricRegressions.isEmpty
        guard decision.accepted == expectedAccepted else {
            throw ValidationError.acceptedCheckpointMismatch("accepted")
        }
        guard decision.bestCandidateID == eliteArchive.bestCandidateID,
              decision.bestFitness == eliteArchive.bestFitness else {
            throw ValidationError.acceptedCheckpointMismatch("best-candidate")
        }
        if let bestCandidateID = decision.bestCandidateID {
            guard let bestCandidate = candidates.first(where: { $0.candidateID == bestCandidateID }) else {
                throw ValidationError.acceptedCheckpointCandidateMissing(bestCandidateID)
            }
            guard decision.bestCheckpointID == bestCandidate.checkpointID,
                  decision.bestCheckpointURL == bestCandidate.checkpointURL else {
                throw ValidationError.acceptedCheckpointMismatch("best-checkpoint")
            }
        } else {
            guard decision.bestCheckpointID == nil,
                  decision.bestCheckpointURL == nil,
                  decision.bestFitness == nil else {
                throw ValidationError.acceptedCheckpointMismatch("missing-best-candidate")
            }
        }
        if decision.accepted {
            guard let candidateID = decision.candidateID else {
                throw ValidationError.acceptedCheckpointMismatch("candidate-id")
            }
            guard let candidate = candidates.first(where: { $0.candidateID == candidateID }) else {
                throw ValidationError.acceptedCheckpointCandidateMissing(candidateID)
            }
            guard eliteArchive.bestCandidateID == candidateID,
                  decision.checkpointID == candidate.checkpointID,
                  decision.checkpointURL == candidate.checkpointURL,
                  decision.scalarFitness == eliteArchive.bestFitness,
                  decision.bestCandidateID == candidateID else {
                throw ValidationError.acceptedCheckpointMismatch(candidateID)
            }
            guard let checkpointID = candidate.checkpointID,
                  let checkpointURL = candidate.checkpointURL,
                  let checkpointReference = decision.checkpointReference else {
                throw ValidationError.acceptedCheckpointMismatch("checkpoint-reference")
            }
            if manifest.candidateAcceptanceMode == .dedicatedEvaluation {
                guard acceptanceEvaluations.first(where: {
                    $0.candidateID == candidateID && $0.accepted
                })?.checkpointReference == checkpointReference else {
                    throw ValidationError.acceptedCheckpointMismatch("acceptance-checkpoint-reference")
                }
            }
            do {
                try EvolutionCheckpointIntegrity().validate(
                    checkpointReference,
                    expectedCheckpointID: checkpointID,
                    expectedCheckpointURL: checkpointURL,
                    artifactRoot: artifactDirectory
                )
            } catch {
                throw ValidationError.invalidCheckpointReference(
                    candidateID: candidateID,
                    reason: String(describing: error)
                )
            }
        } else {
            guard decision.candidateID == nil,
                  decision.checkpointID == nil,
                  decision.checkpointURL == nil,
                  decision.checkpointReference == nil,
                  decision.scalarFitness == nil else {
                throw ValidationError.acceptedCheckpointMismatch("rejected-candidate")
            }
        }

        let expectedIncumbentFitness = decision.incumbentCandidateID.flatMap { candidateID in
            fitness.first { $0.candidateID == candidateID }?.scalarFitness
        }
        guard decision.incumbentFitness == expectedIncumbentFitness else {
            throw ValidationError.acceptedCheckpointMismatch("incumbent-fitness")
        }
        let expectedDelta = zipOptional(decision.bestFitness, decision.incumbentFitness).map { best, incumbent in
            best - incumbent
        }
        guard decision.bestVsIncumbentDelta == expectedDelta else {
            throw ValidationError.acceptedCheckpointMismatch("best-vs-incumbent")
        }
        let expectedPublishRegressions = manifest.candidateAcceptanceMode == .searchGateOnly
            ? publishMetricRegressions(
                bestCandidateID: decision.bestCandidateID,
                incumbentCandidateID: decision.incumbentCandidateID,
                fitness: fitness
            )
            : []
        guard decision.publishMetricRegressions == expectedPublishRegressions else {
            throw ValidationError.acceptedCheckpointMismatch("publish-metric-regressions")
        }
    }

    func publishMetricRegressions(
        bestCandidateID: String?,
        incumbentCandidateID: String?,
        fitness: [FitnessSummary]
    ) -> [String] {
        guard let bestCandidateID,
              let incumbentCandidateID,
              let best = fitness.first(where: { $0.candidateID == bestCandidateID }),
              let incumbent = fitness.first(where: { $0.candidateID == incumbentCandidateID }) else {
            return []
        }
        var reasons: [String] = []
        if best.taskPassRate < incumbent.taskPassRate {
            reasons.append("publish-metric-regression:taskPassRate:\(best.taskPassRate)<\(incumbent.taskPassRate)")
        }
        if best.safetyViolationRate > incumbent.safetyViolationRate {
            reasons.append("publish-metric-regression:safetyViolationRate:\(best.safetyViolationRate)>\(incumbent.safetyViolationRate)")
        }
        if let bestHoldTimeRatio = best.holdTimeRatio,
           let incumbentHoldTimeRatio = incumbent.holdTimeRatio,
           bestHoldTimeRatio < incumbentHoldTimeRatio {
            reasons.append("publish-metric-regression:holdTimeRatio:\(bestHoldTimeRatio)<\(incumbentHoldTimeRatio)")
        }
        if !best.failureReasons.isEmpty {
            reasons.append("publish-metric-regression:failureReasons:\(best.failureReasons.joined(separator: ","))")
        }
        return reasons
    }
}
