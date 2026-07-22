import Foundation
import KuyuTrainingContracts

extension EvolutionRunOrchestrator {
    func candidateAcceptance(
        config: EvolutionRunConfig,
        candidate: GenomeCandidate,
        incumbentCandidate: GenomeCandidate,
        searchFitness: FitnessSummary,
        artifactDirectory: URL,
        progressReporter: (any TrainingProgressReporting)?,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)?
    ) async throws -> EvolutionCandidateAcceptanceRecord? {
        guard let candidateAcceptanceStage else { return nil }

        onEvent?(.candidateAcceptanceStarted(
            generationIndex: candidate.generationIndex,
            candidateID: candidate.candidateID
        ))
        guard let checkpointID = candidate.checkpointID,
              let checkpointURL = candidate.checkpointURL else {
            throw RunError.acceptanceFailed("candidate-checkpoint-missing:\(candidate.candidateID)")
        }
        let checkpointIntegrity = EvolutionCheckpointIntegrity()
        let checkpointReference = try checkpointIntegrity.reference(
            checkpointID: checkpointID,
            checkpointURL: checkpointURL,
            artifactRoot: artifactDirectory
        )
        guard let incumbentCheckpointID = incumbentCandidate.checkpointID,
              let incumbentCheckpointURL = incumbentCandidate.checkpointURL else {
            throw RunError.acceptanceFailed(
                "incumbent-checkpoint-missing:\(incumbentCandidate.candidateID)"
            )
        }
        let incumbentCheckpointReference = try checkpointIntegrity.reference(
            checkpointID: incumbentCheckpointID,
            checkpointURL: incumbentCheckpointURL,
            artifactRoot: artifactDirectory
        )
        let acceptanceDirectory = artifactDirectory.appendingPathComponent("acceptance", isDirectory: true)
        let acceptanceResult = try await candidateAcceptanceStage.evaluator.evaluateAcceptance(
            request: EvolutionCandidateAcceptanceRequest(
                config: config,
                candidate: candidate,
                incumbentCandidate: incumbentCandidate,
                searchFitness: searchFitness,
                artifactDirectory: acceptanceDirectory,
                workerCount: config.workerCount
            ),
            progressReporter: progressReporter
        )
        let acceptanceFitness = acceptanceResult.fitness
        let acceptanceIncumbentFitness = acceptanceResult.incumbentFitness
        guard acceptanceFitness.runID == config.runID,
              acceptanceFitness.generationIndex == candidate.generationIndex,
              acceptanceFitness.candidateID == candidate.candidateID,
              acceptanceFitness.taskID == config.taskID else {
            throw RunError.acceptanceFailed(
                "identity-mismatch: expected=\(config.runID)/\(candidate.generationIndex)/\(candidate.candidateID)/\(config.taskID) "
                    + "actual=\(acceptanceFitness.runID)/\(acceptanceFitness.generationIndex)/\(acceptanceFitness.candidateID)/\(acceptanceFitness.taskID)"
            )
        }
        guard acceptanceIncumbentFitness.runID == config.runID,
              acceptanceIncumbentFitness.generationIndex == incumbentCandidate.generationIndex,
              acceptanceIncumbentFitness.candidateID == incumbentCandidate.candidateID,
              acceptanceIncumbentFitness.taskID == config.taskID else {
            throw RunError.acceptanceFailed(
                "incumbent-identity-mismatch: expected=\(config.runID)/"
                    + "\(incumbentCandidate.generationIndex)/\(incumbentCandidate.candidateID)/"
                    + "\(config.taskID) actual=\(acceptanceIncumbentFitness.runID)/"
                    + "\(acceptanceIncumbentFitness.generationIndex)/"
                    + "\(acceptanceIncumbentFitness.candidateID)/"
                    + "\(acceptanceIncumbentFitness.taskID)"
            )
        }
        try EvolutionCandidateAcceptanceResultValidator().validate(
            acceptanceResult,
            acceptanceDirectory: acceptanceDirectory
        )
        try checkpointIntegrity.validate(
            checkpointReference,
            expectedCheckpointID: checkpointID,
            expectedCheckpointURL: checkpointURL,
            artifactRoot: artifactDirectory
        )
        try checkpointIntegrity.validate(
            incumbentCheckpointReference,
            expectedCheckpointID: incumbentCheckpointID,
            expectedCheckpointURL: incumbentCheckpointURL,
            artifactRoot: artifactDirectory
        )

        let gateReport: EvolutionGateReport
        switch candidateAcceptanceStage.promotionCriterion {
        case .incumbentRelative:
            gateReport = candidateAcceptanceStage.gatePolicy.acceptanceReport(
                runID: config.runID,
                candidate: acceptanceFitness,
                incumbent: acceptanceIncumbentFitness
            )
        case .absoluteThreshold:
            gateReport = candidateAcceptanceStage.gatePolicy.absoluteAcceptanceReport(
                runID: config.runID,
                candidate: acceptanceFitness,
                incumbent: acceptanceIncumbentFitness
            )
        }
        let record = EvolutionCandidateAcceptanceRecord(
            runID: config.runID,
            generationIndex: candidate.generationIndex,
            candidateID: candidate.candidateID,
            fitness: acceptanceFitness,
            checkpointReference: checkpointReference,
            incumbentCandidateID: incumbentCandidate.candidateID,
            incumbentFitness: acceptanceIncumbentFitness,
            incumbentCheckpointReference: incumbentCheckpointReference,
            evaluationContract: acceptanceResult.evaluationContract,
            evidence: acceptanceResult.evidence,
            accepted: gateReport.accepted,
            rejectionReasons: gateReport.rejectionReasons
        )
        onEvent?(.candidateAcceptanceCompleted(record))
        return record
    }

    func finishSearch(
        manifest: EvolutionRunManifest,
        config: EvolutionRunConfig,
        searchFailureReason: String?,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        evaluationTraces: [EvolutionCandidateEvaluationTrace],
        restoredAcceptanceEvaluations: [EvolutionCandidateAcceptanceRecord],
        bestSearchFitness: FitnessSummary?,
        artifactDirectory: URL,
        progressReporter: (any TrainingProgressReporting)?,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)?
    ) async -> EvolutionRunResult {
        guard let bestSearchFitness else {
            return await finish(
                manifest: manifest,
                state: .rejected,
                failureReason: searchFailureReason,
                generations: generations,
                candidates: candidates,
                fitness: fitness,
                evaluationTraces: evaluationTraces,
                acceptanceEvaluations: restoredAcceptanceEvaluations,
                artifactDirectory: artifactDirectory,
                onEvent: onEvent
            )
        }
        guard let candidate = candidates.first(where: { $0.candidateID == bestSearchFitness.candidateID }) else {
            return await finish(
                manifest: manifest,
                state: .failed,
                failureReason: "evolution-acceptance-failed: search-winner-missing:\(bestSearchFitness.candidateID)",
                generations: generations,
                candidates: candidates,
                fitness: fitness,
                evaluationTraces: evaluationTraces,
                acceptanceEvaluations: restoredAcceptanceEvaluations,
                bestFitness: bestSearchFitness,
                artifactDirectory: artifactDirectory,
                onEvent: onEvent
            )
        }
        guard candidateAcceptanceStage == nil
                || candidates.contains(where: { $0.isIncumbent == true }) else {
            return await finish(
                manifest: manifest,
                state: .failed,
                failureReason: "evolution-acceptance-failed: incumbent-candidate-missing",
                generations: generations,
                candidates: candidates,
                fitness: fitness,
                evaluationTraces: evaluationTraces,
                acceptanceEvaluations: restoredAcceptanceEvaluations,
                bestFitness: bestSearchFitness,
                artifactDirectory: artifactDirectory,
                onEvent: onEvent
            )
        }
        let incumbentCandidate = candidates.first(where: { $0.isIncumbent == true })

        let acceptanceRecord: EvolutionCandidateAcceptanceRecord?
        do {
            acceptanceRecord = try await candidateAcceptance(
                config: config,
                candidate: candidate,
                incumbentCandidate: incumbentCandidate ?? candidate,
                searchFitness: bestSearchFitness,
                artifactDirectory: artifactDirectory,
                progressReporter: progressReporter,
                onEvent: onEvent
            )
        } catch is CancellationError {
            return await finish(
                manifest: manifest,
                state: .cancelled,
                failureReason: "cancelled",
                generations: generations,
                candidates: candidates,
                fitness: fitness,
                evaluationTraces: evaluationTraces,
                acceptanceEvaluations: restoredAcceptanceEvaluations,
                bestFitness: bestSearchFitness,
                artifactDirectory: artifactDirectory,
                onEvent: onEvent
            )
        } catch {
            return await finish(
                manifest: manifest,
                state: .failed,
                failureReason: "evolution-acceptance-failed: \(error)",
                generations: generations,
                candidates: candidates,
                fitness: fitness,
                evaluationTraces: evaluationTraces,
                acceptanceEvaluations: restoredAcceptanceEvaluations,
                bestFitness: bestSearchFitness,
                artifactDirectory: artifactDirectory,
                onEvent: onEvent
            )
        }

        var acceptanceEvaluations = restoredAcceptanceEvaluations
        if let acceptanceRecord {
            acceptanceEvaluations.append(acceptanceRecord)
        }
        let accepted = acceptanceRecord?.accepted ?? true
        let acceptanceFailureReason = acceptanceRecord.map { record in
            record.rejectionReasons.map { "acceptance:\($0)" }.joined(separator: ",")
        }
        return await finish(
            manifest: manifest,
            state: accepted ? .completed : .rejected,
            failureReason: accepted ? searchFailureReason : acceptanceFailureReason,
            generations: generations,
            candidates: candidates,
            fitness: fitness,
            evaluationTraces: evaluationTraces,
            acceptanceEvaluations: acceptanceEvaluations,
            bestFitness: bestSearchFitness,
            artifactDirectory: artifactDirectory,
            onEvent: onEvent
        )
    }
}
