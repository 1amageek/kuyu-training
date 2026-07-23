import Foundation

extension TrainingProjectEvidencePackValidator {
    func validateObservabilityArtifacts(
        _ artifacts: [TrainingProjectEvidencePack.ObservabilityArtifactEvidence]
    ) throws {
        var runIDs: Set<String> = []
        var paths: Set<String> = []
        for artifact in artifacts {
            let runID = artifact.runID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !runID.isEmpty else { throw ValidationError.emptyObservabilityRunID }
            guard runIDs.insert(runID).inserted else {
                throw ValidationError.duplicateObservabilityRunID(runID)
            }
            guard !artifact.scenarioID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.emptyObservabilityScenarioID(runID)
            }
            try validatePositiveObservabilityCount(
                artifact.descendingSnapshotCount,
                runID: runID,
                field: "descendingSnapshotCount"
            )
            try validatePositiveObservabilityCount(
                artifact.upwardSummaryCount,
                runID: runID,
                field: "upwardSummaryCount"
            )
            try validatePositiveObservabilityCount(
                artifact.arbitrationDecisionCount,
                runID: runID,
                field: "arbitrationDecisionCount"
            )
            guard artifact.latencyBudgetViolationCount >= 0 else {
                throw ValidationError.invalidObservabilityCount(
                    runID: runID,
                    field: "latencyBudgetViolationCount",
                    count: artifact.latencyBudgetViolationCount
                )
            }
            let path = artifact.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { throw ValidationError.emptyObservabilityPath }
            guard !path.hasPrefix("/") else {
                throw ValidationError.absoluteObservabilityPath(path)
            }
            let components = path.split(separator: "/").map(String.init)
            guard !components.contains("..") else {
                throw ValidationError.escapingObservabilityPath(path)
            }
            guard paths.insert(path).inserted else {
                throw ValidationError.duplicateObservabilityPath(path)
            }
        }
    }

    func validatePositiveObservabilityCount(
        _ count: Int,
        runID: String,
        field: String
    ) throws {
        guard count > 0 else {
            throw ValidationError.invalidObservabilityCount(
                runID: runID,
                field: field,
                count: count
            )
        }
    }
}
