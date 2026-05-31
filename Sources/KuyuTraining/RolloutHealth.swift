import Foundation
import KuyuCore

public struct RolloutHealth: Sendable, Codable, Equatable {
    public private(set) var episodeCount: Int
    public private(set) var doneCount: Int
    public private(set) var truncatedCount: Int
    public private(set) var failureCount: Int
    public private(set) var cancelledCount: Int
    public private(set) var curriculumHorizonCount: Int
    public private(set) var nonFiniteMetricCount: Int
    public private(set) var rewardSum: Double
    public private(set) var maxOmega: Double
    public private(set) var maxTilt: Double
    public private(set) var minAltitude: Double?

    public init() {
        episodeCount = 0
        doneCount = 0
        truncatedCount = 0
        failureCount = 0
        cancelledCount = 0
        curriculumHorizonCount = 0
        nonFiniteMetricCount = 0
        rewardSum = 0
        maxOmega = 0
        maxTilt = 0
        minAltitude = nil
    }

    public init(episodes: [RolloutEpisode]) {
        self.init()
        add(episodes)
    }

    public var failureRate: Double {
        Double(failureCount) / Double(max(episodeCount, 1))
    }

    public var rewardAverage: Double {
        rewardSum / Double(max(episodeCount, 1))
    }

    public var nonCurriculumTruncationCount: Int {
        max(0, truncatedCount - curriculumHorizonCount)
    }

    public var summary: String {
        let minAltitudeText = minAltitude.map { String(format: "%.3f", $0) } ?? "n/a"
        return [
            "episodes=\(episodeCount)",
            "fail=\(failureCount)",
            "trunc=\(truncatedCount)",
            "horizon=\(curriculumHorizonCount)",
            "cancel=\(cancelledCount)",
            "rewardAvg=\(String(format: "%.4f", rewardAverage))",
            "omega=\(String(format: "%.3f", maxOmega))",
            "tilt=\(String(format: "%.3f", maxTilt))",
            "minZ=\(minAltitudeText)",
            "nonFinite=\(nonFiniteMetricCount)",
        ].joined(separator: " ")
    }

    public mutating func add(_ episodes: [RolloutEpisode]) {
        for episode in episodes {
            add(episode)
        }
    }

    public mutating func add(_ episode: RolloutEpisode) {
        episodeCount += 1
        if episode.done {
            doneCount += 1
        }
        if episode.truncated {
            truncatedCount += 1
        }
        if episode.failureReason != nil {
            failureCount += 1
        }
        if episode.cancelled {
            cancelledCount += 1
        }
        if episode.terminalReason == RolloutTerminalReason.curriculumHorizon {
            curriculumHorizonCount += 1
        }
        if episode.rewardSum.isFinite {
            rewardSum += episode.rewardSum
        } else {
            nonFiniteMetricCount += 1
        }
        for step in episode.steps {
            addStepMetrics(step)
        }
    }

    public func isAcceptable(
        relativeTo baseline: RolloutHealth,
        policy: RolloutHealthAcceptancePolicy = .conservative
    ) -> Bool {
        policy.accepts(candidate: self, relativeTo: baseline)
    }

    private mutating func addStepMetrics(_ step: EnvironmentStep) {
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
}
