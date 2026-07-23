import KuyuTrainingValidation

public extension GeneratedTrainingArtifactCompatibilityVerifier {
    func verify(
        _ request: GeneratedTrainingArtifactCompatibilityRequest
    ) throws -> GeneratedTrainingArtifactCompatibilityReport {
        guard request.runArtifactDirectory != nil
            || request.probeArtifactDirectory != nil
            || request.evolutionArtifactDirectory != nil
            || request.checkpointEvaluation != nil
            || request.projectEvidencePackDirectory != nil
            || request.observabilityArtifactURL != nil
            || request.summaryOutcomeDirectory != nil else {
            throw VerificationError.emptyRequest
        }
        let runArtifacts = try request.runArtifactDirectory.map(validatedRunArtifacts)
        let probeArtifacts = try request.probeArtifactDirectory.map(validatedProbeArtifacts)
        let evolutionArtifacts = try request.evolutionArtifactDirectory.map(validatedEvolutionArtifacts)
        let checkpointEvaluationArtifact = try request.checkpointEvaluation.map(validatedCheckpointEvaluationArtifact)
        let projectEvidencePack = try request.projectEvidencePackDirectory.map(validatedProjectEvidencePack)
        let observabilityArtifact = try request.observabilityArtifactURL.map(validatedObservabilityArtifact)
        let summaryOutcomeArtifact = try request.summaryOutcomeDirectory.map(validatedSummaryOutcomeArtifact)
        try validateCompatibility(runArtifacts: runArtifacts, probeArtifacts: probeArtifacts)
        return GeneratedTrainingArtifactCompatibilityReport(
            runArtifacts: runArtifacts,
            probeArtifacts: probeArtifacts,
            evolutionArtifacts: evolutionArtifacts,
            checkpointEvaluationArtifact: checkpointEvaluationArtifact,
            projectEvidencePack: projectEvidencePack,
            observabilityArtifact: observabilityArtifact,
            summaryOutcomeArtifact: summaryOutcomeArtifact
        )
    }

    private func validateCompatibility(
        runArtifacts: TrainingRunArtifactBundle?,
        probeArtifacts: TrainingProbeArtifactBundle?
    ) throws {
        guard let runArtifacts, let probeArtifacts else {
            return
        }
        guard runArtifacts.manifest.runID == probeArtifacts.training.manifest.runID else {
            throw VerificationError.incompatibleRunAndProbeArtifacts(
                runID: runArtifacts.manifest.runID,
                probeTrainingRunID: probeArtifacts.training.manifest.runID
            )
        }
    }
}
