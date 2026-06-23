import Foundation
import KuyuCore
import KuyuTrainingContracts
import KuyuTrainingValidation

public struct WorldModelTrainingTuple: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case nonFiniteReward(Double)
        case invalidContinue(Double)
    }

    public let episodeId: String
    public let stepIndex: Int
    public let observation: EnvironmentObservation
    public let action: EnvironmentAction
    public let physicsPrediction: EnvironmentObservation
    public let actualObservation: EnvironmentObservation
    public let reward: Double
    public let continueValue: Double
    public let done: Bool
    public let truncated: Bool
    public let robotManifestID: String?
    public let scenarioId: String
    public let seed: UInt64

    public init(
        episodeId: String,
        stepIndex: Int,
        observation: EnvironmentObservation,
        action: EnvironmentAction,
        physicsPrediction: EnvironmentObservation,
        actualObservation: EnvironmentObservation,
        reward: Double,
        continueValue: Double,
        done: Bool,
        truncated: Bool,
        robotManifestID: String?,
        scenarioId: String,
        seed: UInt64
    ) throws {
        guard reward.isFinite else { throw ValidationError.nonFiniteReward(reward) }
        guard continueValue == 0.0 || continueValue == 1.0 else {
            throw ValidationError.invalidContinue(continueValue)
        }
        self.episodeId = episodeId
        self.stepIndex = stepIndex
        self.observation = observation
        self.action = action
        self.physicsPrediction = physicsPrediction
        self.actualObservation = actualObservation
        self.reward = reward
        self.continueValue = continueValue
        self.done = done
        self.truncated = truncated
        self.robotManifestID = robotManifestID
        self.scenarioId = scenarioId
        self.seed = seed
    }
}

public struct WorldModelTupleBuilder: Sendable {
    public init() {}

    public func makeTuples(from episode: RolloutEpisode) throws -> [WorldModelTrainingTuple] {
        guard episode.steps.count >= 2 else { return [] }
        var tuples: [WorldModelTrainingTuple] = []
        tuples.reserveCapacity(episode.steps.count - 1)

        for index in 0..<(episode.steps.count - 1) {
            let current = episode.steps[index]
            let next = episode.steps[index + 1]
            let terminal = next.done || next.truncated
            tuples.append(try WorldModelTrainingTuple(
                episodeId: episode.episodeId,
                stepIndex: index,
                observation: current.observation,
                action: action(from: current.log),
                physicsPrediction: physicsPrediction(from: current.observation, to: next.observation),
                actualObservation: next.observation,
                reward: next.reward,
                continueValue: terminal ? 0.0 : 1.0,
                done: next.done,
                truncated: next.truncated,
                robotManifestID: episode.robotManifestID,
                scenarioId: episode.scenarioId,
                seed: episode.seed
            ))
        }

        return tuples
    }

    public func makeTuples(from episodes: [RolloutEpisode]) throws -> [WorldModelTrainingTuple] {
        try episodes.flatMap { episode in
            try makeTuples(from: episode)
        }
    }

    private func action(from log: WorldStepLog) -> EnvironmentAction {
        if !log.actuatorValues.isEmpty {
            return .actuatorValues(log.actuatorValues)
        }
        return .driveIntents(log.driveIntents, corrections: log.reflexCorrections)
    }

    private func physicsPrediction(
        from current: EnvironmentObservation,
        to next: EnvironmentObservation
    ) -> EnvironmentObservation {
        let dt = max(0.0, next.time.time - current.time.time)
        return EnvironmentObservation(
            time: next.time,
            sensorSamples: next.sensorSamples,
            plantState: predictedPlantState(from: current.plantState, dt: dt),
            safetyTrace: next.safetyTrace,
            actuatorTelemetry: next.actuatorTelemetry,
            disturbances: next.disturbances
        )
    }

    private func predictedPlantState(from snapshot: PlantStateSnapshot, dt: Double) -> PlantStateSnapshot {
        let root = snapshot.root
        return PlantStateSnapshot(
            root: RigidBodySnapshot(
                id: root.id,
                position: Axis3(
                    x: root.position.x + root.velocity.x * dt,
                    y: root.position.y + root.velocity.y * dt,
                    z: root.position.z + root.velocity.z * dt
                ),
                velocity: root.velocity,
                orientation: root.orientation,
                angularVelocity: root.angularVelocity
            ),
            bodies: snapshot.bodies,
            scalars: snapshot.scalars
        )
    }
}
