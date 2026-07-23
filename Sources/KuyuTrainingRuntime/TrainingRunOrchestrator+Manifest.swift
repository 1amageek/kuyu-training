import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuTrainingValidation

extension TrainingRunOrchestrator {
    func robotManifestFailureResult(
        config: TrainingRunConfig,
        runRequest: SimulationRunRequest,
        artifactDirectory: URL,
        startedAt: Date,
        error: any Error,
        onEvent: (@Sendable (TrainingRunEvent) -> Void)?
    ) async -> TrainingRunResult {
        let manifest = LearningRunManifest(
            runID: config.runID,
            mode: config.mode,
            configHash: requestHash(runRequest, robotIdentity: nil),
            suiteID: runRequest.taskMode.rawValue,
            seedSet: [],
            policyID: config.policyID,
            parentCheckpointID: config.parentCheckpointID,
            outputCheckpointID: nil,
            workerCount: config.workerCount,
            startedAt: startedAt,
            terminalState: .failed,
            failureReason: "robotManifestIdentityFailed: \(error)"
        )
        onEvent?(.started(manifest))
        return await finish(
            manifest: manifest,
            metrics: [],
            bestCheckpointID: nil,
            bestCheckpointURL: nil,
            finalCheckpointID: nil,
            finalCheckpointURL: nil,
            artifactDirectory: artifactDirectory,
            state: .failed,
            failureReason: manifest.failureReason,
            onEvent: onEvent
        )
    }

    func manifestRecordingScenarioIdentity(
        _ manifest: LearningRunManifest,
        output: TrainingScenarioRunOutput
    ) -> LearningRunManifest {
        LearningRunManifest(
            runID: manifest.runID,
            mode: manifest.mode,
            robotManifestID: manifest.robotManifestID,
            robotManifestHash: manifest.robotManifestHash,
            configHash: output.logs.first?.log.configHash ?? manifest.configHash,
            suiteID: manifest.suiteID,
            seedSet: output.logs.map { $0.key.seed.rawValue },
            policyID: manifest.policyID,
            parentCheckpointID: manifest.parentCheckpointID,
            outputCheckpointID: nil,
            workerCount: manifest.workerCount,
            startedAt: manifest.startedAt,
            terminalState: .running
        )
    }
}
