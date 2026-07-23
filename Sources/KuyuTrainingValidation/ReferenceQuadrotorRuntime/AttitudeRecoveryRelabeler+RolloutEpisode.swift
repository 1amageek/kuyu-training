import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios

public extension AttitudeRecoveryRelabeler {
    func relabelEpisode(
        _ episode: RolloutEpisode,
        definition: ReferenceQuadrotorScenarioDefinition,
        parameters: ReferenceQuadrotorParameters,
        gains: ImuRateDampingCutGains,
        config: AttitudeRecoveryRelabelConfig = AttitudeRecoveryRelabelConfig()
    ) throws -> RolloutEpisode {
        try relabelEpisode(
            episode,
            definition: definition,
            parameters: parameters,
            gains: gains,
            config: config,
            startIndex: 0
        )
    }

    func relabelEpisode(
        _ episode: RolloutEpisode,
        definition: ReferenceQuadrotorScenarioDefinition,
        parameters: ReferenceQuadrotorParameters,
        gains: ImuRateDampingCutGains,
        config: AttitudeRecoveryRelabelConfig = AttitudeRecoveryRelabelConfig(),
        startIndex: Int
    ) throws -> RolloutEpisode {
        guard !episode.steps.isEmpty else {
            return episode
        }
        var teacher = try makeTeacher(
            definition: definition,
            parameters: parameters,
            gains: gains,
            config: config
        )
        let boundedStartIndex = min(max(0, startIndex), episode.steps.count - 1)
        var relabeledSteps: [EnvironmentStep] = []
        relabeledSteps.reserveCapacity(episode.steps.count - boundedStartIndex)
        for (index, step) in episode.steps.enumerated() {
            let relabeledLog = try relabel(event: step.log, teacher: &teacher)
            guard index >= boundedStartIndex else { continue }
            relabeledSteps.append(try EnvironmentStep(
                observation: step.observation,
                reward: step.reward,
                done: step.done,
                truncated: step.truncated,
                info: step.info,
                log: relabeledLog
            ))
        }
        let rewardSum = boundedStartIndex == 0
            ? episode.rewardSum
            : relabeledSteps.map(\.reward).reduce(0, +)
        let durationSeconds = boundedStartIndex == 0
            ? episode.durationSeconds
            : relabeledSteps.last.map { last in
                last.log.time.time - (relabeledSteps.first?.log.time.time ?? last.log.time.time)
            } ?? 0
        return RolloutEpisode(
            episodeId: episode.episodeId,
            scenarioId: episode.scenarioId,
            seed: episode.seed,
            workerIndex: episode.workerIndex,
            policyId: config.policyId,
            configHash: episode.configHash,
            robotManifestID: episode.robotManifestID,
            rewardDescriptor: episode.rewardDescriptor,
            rewardSum: rewardSum,
            done: episode.done,
            truncated: episode.truncated,
            terminalReason: episode.terminalReason,
            failureReason: episode.failureReason,
            failureTime: episode.failureTime,
            stepCount: relabeledSteps.count,
            workerCount: episode.workerCount,
            maxSteps: episode.maxSteps,
            durationSeconds: durationSeconds,
            cancelled: episode.cancelled,
            steps: relabeledSteps,
            transitions: nil,
            physicsTimeStep: episode.physicsTimeStep,
            controlPeriodSteps: episode.controlPeriodSteps,
            taskReference: episode.taskReference
        )
    }
}
