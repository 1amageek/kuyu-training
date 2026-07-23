import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

extension TrainingProbeOrchestrator {
    func makeRecoveryRelabelStatus(
        comparison: TrainingProbeComparison,
        trainedOutput: TrainingScenarioRunOutput?,
        trainingRequest: SimulationRunRequest,
        artifactDirectory: URL
    ) async -> TrainingProbeRecoveryRelabelStatus {
        guard !comparison.probeAccepted else {
            return .skipped(reason: "probe-accepted")
        }
        guard let trainedOutput else {
            return .skipped(reason: "trained-output-unavailable")
        }
        let includeSuccessfulScenarios = !comparison.teacherDivergenceNonRegression
            || !comparison.policySatisfied
        let directory = artifactDirectory.appendingPathComponent("recovery-datasets", isDirectory: true)
        do {
            guard let report = try await scenarioExecutor.writeRecoveryRelabelDataset(
                output: trainedOutput,
                request: trainingRequest,
                to: directory,
                includeSuccessfulScenarios: includeSuccessfulScenarios
            ) else {
                return .skipped(reason: "recovery-relabel-unavailable")
            }
            guard report.relabeledEntryCount > 0 else {
                return .skipped(reason: "recovery-relabel-empty")
            }
            return TrainingProbeRecoveryRelabelStatus(
                attempted: true,
                datasetDirectory: directory,
                report: report,
                failureReason: nil
            )
        } catch {
            return TrainingProbeRecoveryRelabelStatus(
                attempted: true,
                datasetDirectory: directory,
                report: nil,
                failureReason: "recovery-relabel-failed: \(error)"
            )
        }
    }
}
