import KuyuScenarios

extension RolloutRunner {
    func checkCancellation(definition: ReferenceQuadrotorScenarioDefinition) throws {
        if Task.isCancelled {
            throw RolloutError.cancelled(
                scenarioId: definition.config.id.rawValue,
                seed: definition.config.seed.rawValue
            )
        }
    }

    func checkWallTimeLimit(
        definition: ReferenceQuadrotorScenarioDefinition,
        start: ContinuousClock.Instant
    ) throws {
        guard let maxWallTimeSeconds = limits.maxWallTimeSeconds else { return }
        let elapsed = start.duration(to: ContinuousClock.now)
        let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        if elapsedSeconds > maxWallTimeSeconds {
            throw RolloutError.exceededMaxWallTime(
                scenarioId: definition.config.id.rawValue,
                seed: definition.config.seed.rawValue,
                maxWallTimeSeconds: maxWallTimeSeconds
            )
        }
    }

    func checkStepLimit(definition: ReferenceQuadrotorScenarioDefinition, stepCount: Int) throws {
        guard let maxSteps = limits.maxStepsPerEpisode, stepCount >= maxSteps else { return }
        throw RolloutError.exceededMaxSteps(
            scenarioId: definition.config.id.rawValue,
            seed: definition.config.seed.rawValue,
            maxSteps: maxSteps
        )
    }
}
