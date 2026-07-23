import KuyuScenarios

public extension ParallelRolloutCollector {
    func collect(
        definitions: [ReferenceQuadrotorScenarioDefinition],
        policyFactory: any ReferenceQuadrotorPolicyFactory
    ) async throws -> [RolloutEpisode] {
        let shardCount = min(workerCount, max(definitions.count, 1))
        return try await withThrowingTaskGroup(of: [RolloutEpisode].self) { group in
            for workerIndex in 0..<shardCount {
                let workerDefinitions = definitions.enumerated().compactMap { index, definition in
                    index % shardCount == workerIndex ? definition : nil
                }
                guard !workerDefinitions.isEmpty else { continue }
                let runner = runner
                group.addTask {
                    let episodes = try await runner.run(
                        definitions: workerDefinitions,
                        policyFactory: policyFactory,
                        workerIndex: workerIndex
                    )
                    return episodes.map { annotatedEpisode($0, workerCount: workerCount) }
                }
            }

            var episodes: [RolloutEpisode] = []
            episodes.reserveCapacity(definitions.count)
            for try await workerEpisodes in group {
                episodes.append(contentsOf: workerEpisodes)
            }
            return episodes.sorted { lhs, rhs in
                if lhs.scenarioId != rhs.scenarioId { return lhs.scenarioId < rhs.scenarioId }
                if lhs.seed != rhs.seed { return lhs.seed < rhs.seed }
                return lhs.workerIndex < rhs.workerIndex
            }
        }
    }

    private func annotatedEpisode(_ episode: RolloutEpisode, workerCount: Int) -> RolloutEpisode {
        RolloutEpisode(
            episodeId: episode.episodeId,
            scenarioId: episode.scenarioId,
            seed: episode.seed,
            workerIndex: episode.workerIndex,
            policyId: episode.policyId,
            configHash: episode.configHash,
            robotManifestID: episode.robotManifestID,
            rewardDescriptor: episode.rewardDescriptor,
            rewardSum: episode.rewardSum,
            done: episode.done,
            truncated: episode.truncated,
            terminalReason: episode.terminalReason,
            failureReason: episode.failureReason,
            failureTime: episode.failureTime,
            stepCount: episode.stepCount,
            workerCount: workerCount,
            maxSteps: episode.maxSteps,
            durationSeconds: episode.durationSeconds,
            cancelled: episode.cancelled,
            steps: episode.steps,
            transitions: episode.transitions,
            physicsTimeStep: episode.physicsTimeStep,
            controlPeriodSteps: episode.controlPeriodSteps,
            taskReference: episode.taskReference
        )
    }
}
