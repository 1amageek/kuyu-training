import KuyuCore
import KuyuScenarios
extension RolloutRunner {
    func makeEpisode(
        definition: ReferenceQuadrotorScenarioDefinition,
        final: EnvironmentStep,
        steps: [EnvironmentStep],
        transitions: [RolloutTransition],
        policyID: String,
        workerIndex: Int
    ) throws -> RolloutEpisode {
        guard transitions.count == steps.count else {
            throw RolloutError.transitionCountMismatch(expected: steps.count, actual: transitions.count)
        }
        let transitionDuration = definition.config.timeStep.delta * Double(schedule.cut.periodSteps)
        for (index, transition) in transitions.enumerated() {
            let isShortTerminalTransition = index == transitions.count - 1
                && (transition.outcome.done || transition.outcome.truncated)
                && transition.duration <= transitionDuration + 1.0e-9
            guard abs(transition.duration - transitionDuration) <= 1.0e-9
                    || isShortTerminalTransition else {
                throw RolloutError.transitionDurationMismatch(
                    expected: transitionDuration,
                    actual: transition.duration
                )
            }
        }
        let info = final.info
        let episodeId = Self.makeEpisodeId(
            scenarioId: info.scenarioId.rawValue,
            seed: info.seed.rawValue,
            workerIndex: workerIndex
        )
        let taskReference = try TrainingTaskReferenceMetadata(
            altitudeHold: TrainingAltitudeHoldReferenceMetadata(
                reference: ReferenceQuadrotorAltitudeHoldReference(definition: definition)
            )
        )
        return RolloutEpisode(
            episodeId: episodeId,
            scenarioId: info.scenarioId.rawValue,
            seed: info.seed.rawValue,
            workerIndex: workerIndex,
            policyId: policyID,
            configHash: info.configHash,
            robotManifestID: robotManifestID,
            rewardDescriptor: info.rewardDescriptor,
            rewardSum: info.rewardSum,
            done: final.done,
            truncated: final.truncated,
            terminalReason: info.terminalReason,
            failureReason: info.failureReason?.rawValue,
            failureTime: info.failureTime,
            stepCount: info.stepCount,
            workerCount: nil,
            maxSteps: limits.maxStepsPerEpisode,
            durationSeconds: final.log.time.time,
            cancelled: false,
            steps: steps,
            transitions: transitions,
            physicsTimeStep: definition.config.timeStep.delta,
            controlPeriodSteps: schedule.cut.periodSteps,
            taskReference: taskReference
        )
    }
    public static func makeEpisodeId(scenarioId: String, seed: UInt64, workerIndex: Int) -> String {
        "\(scenarioId)#seed=\(seed)#worker=\(workerIndex)"
    }
}
