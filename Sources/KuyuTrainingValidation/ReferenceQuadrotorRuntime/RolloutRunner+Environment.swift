import KuyuScenarios

extension RolloutRunner {
    func makeEnvironment() throws -> ReferenceQuadrotorRLEnvironment {
        if let loadedRobot {
            return try ReferenceQuadrotorRLEnvironment(
                loadedRobot: loadedRobot,
                schedule: schedule,
                determinism: determinism,
                noise: noise,
                worldEnvironment: worldEnvironment,
                hoverThrustScale: hoverThrustScale,
                motorNerveRateLimitPerSecond: motorNerveRateLimitPerSecond,
                motorNerveSmoothingTimeConstant: motorNerveSmoothingTimeConstant
            )
        }
        return ReferenceQuadrotorRLEnvironment(
            parameters: parameters,
            mixer: mixer,
            schedule: schedule,
            determinism: determinism,
            noise: noise,
            worldEnvironment: worldEnvironment,
            hoverThrustScale: hoverThrustScale,
            robotManifestID: robotManifestID,
            motorNerveRateLimitPerSecond: motorNerveRateLimitPerSecond,
            motorNerveSmoothingTimeConstant: motorNerveSmoothingTimeConstant
        )
    }
}
