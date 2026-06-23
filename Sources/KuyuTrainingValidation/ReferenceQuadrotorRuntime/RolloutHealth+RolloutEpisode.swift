import Foundation
import KuyuCore
import KuyuReinforcement

public extension RolloutHealth {
    init(episodes: [RolloutEpisode]) {
        self.init()
        add(episodes)
    }

    mutating func add(_ episodes: [RolloutEpisode]) {
        for episode in episodes {
            add(episode)
        }
    }

    mutating func add(_ episode: RolloutEpisode) {
        let metrics = RolloutEpisodeStabilityMetrics(steps: episode.steps)
        addEpisodeSummary(
            done: episode.done,
            truncated: episode.truncated,
            failureReason: episode.failureReason,
            cancelled: episode.cancelled,
            terminalReason: episode.terminalReason,
            rewardSum: episode.rewardSum,
            maxOmega: metrics.maxOmega,
            maxTilt: metrics.maxTilt,
            minAltitude: metrics.minAltitude,
            terminalStepCount: episode.stepCount,
            nonFiniteMetricCount: metrics.nonFiniteMetricCount
        )
    }
}

private struct RolloutEpisodeStabilityMetrics {
    let maxOmega: Double
    let maxTilt: Double
    let minAltitude: Double?
    let nonFiniteMetricCount: Int

    init(steps: [EnvironmentStep]) {
        var maxOmega = 0.0
        var maxTilt = 0.0
        var minAltitude: Double?
        var nonFiniteMetricCount = 0

        for step in steps {
            let omega = step.log.safetyTrace.omegaMagnitude
            if omega.isFinite {
                maxOmega = max(maxOmega, omega)
            } else {
                nonFiniteMetricCount += 1
            }

            let tilt = step.log.safetyTrace.tiltRadians
            if tilt.isFinite {
                maxTilt = max(maxTilt, tilt)
            } else {
                nonFiniteMetricCount += 1
            }

            let altitude = step.log.plantState.root.position.z
            if altitude.isFinite {
                minAltitude = min(minAltitude ?? altitude, altitude)
            } else {
                nonFiniteMetricCount += 1
            }
        }

        self.maxOmega = maxOmega
        self.maxTilt = maxTilt
        self.minAltitude = minAltitude
        self.nonFiniteMetricCount = nonFiniteMetricCount
    }
}
