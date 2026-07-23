import KuyuCore
import KuyuScenarios

public extension RolloutRunner {
    func run(
        definitions: [ReferenceQuadrotorScenarioDefinition],
        policyFactory: any ReferenceQuadrotorPolicyFactory,
        workerIndex: Int = 0
    ) async throws -> [RolloutEpisode] {
        let workerPolicyFactory = try policyFactory.workerScopedFactory(workerIndex: workerIndex)
        var episodes: [RolloutEpisode] = []
        episodes.reserveCapacity(definitions.count)
        for definition in definitions {
            let episode = try await runEpisode(
                definition: definition,
                policyFactory: workerPolicyFactory,
                workerIndex: workerIndex
            )
            episodes.append(episode)
        }
        return episodes
    }

    func runEpisode(
        definition: ReferenceQuadrotorScenarioDefinition,
        policyFactory: any ReferenceQuadrotorPolicyFactory,
        workerIndex: Int = 0
    ) async throws -> RolloutEpisode {
        var environment = try makeEnvironment()
        var observation = try environment.reset(seed: definition.config.seed, scenario: definition)
        var policy = try policyFactory.makePolicy(definition: definition, workerIndex: workerIndex)
        var steps: [EnvironmentStep] = []
        var transitions: [RolloutTransition] = []
        let plannedStepCount = Int((definition.config.duration / definition.config.timeStep.delta).rounded(.down))
        steps.reserveCapacity(min(plannedStepCount, limits.maxStepsPerEpisode ?? plannedStepCount))
        let start = ContinuousClock.now

        while true {
            try checkCancellation(definition: definition)
            try checkWallTimeLimit(definition: definition, start: start)
            try checkStepLimit(definition: definition, stepCount: steps.count)

            let action = try await policy.action(for: observation)
            let step = try environment.step(action: action)
            transitions.append(try RolloutTransition(
                decisionID: Self.makeDecisionID(
                    scenarioId: definition.config.id.rawValue,
                    seed: definition.config.seed.rawValue,
                    workerIndex: workerIndex,
                    decisionIndex: transitions.count
                ),
                actionObservation: observation,
                action: action,
                outcome: step
            ))
            steps.append(step)
            observation = step.observation
            if step.done || step.truncated {
                break
            }
        }

        guard let final = steps.last else {
            throw RolloutError.emptyEpisode(
                scenarioId: definition.config.id.rawValue,
                seed: definition.config.seed.rawValue
            )
        }
        return try makeEpisode(
            definition: definition,
            final: final,
            steps: steps,
            transitions: transitions,
            policyID: policyFactory.policyID,
            workerIndex: workerIndex
        )
    }

    static func makeDecisionID(
        scenarioId: String,
        seed: UInt64,
        workerIndex: Int,
        decisionIndex: Int
    ) -> String {
        "\(scenarioId)#seed=\(seed)#worker=\(workerIndex)#decision=\(decisionIndex)"
    }
}
