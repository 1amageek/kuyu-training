import Foundation
import KuyuCore

public struct RolloutHealth: Sendable, Codable, Equatable {
    public private(set) var episodeCount: Int
    public private(set) var doneCount: Int
    public private(set) var truncatedCount: Int
    public private(set) var failureCount: Int
    public private(set) var cancelledCount: Int
    public private(set) var horizonLimitCount: Int
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
        horizonLimitCount = 0
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

    public var nonHorizonTruncationCount: Int {
        max(0, truncatedCount - horizonLimitCount)
    }

    public var summary: String {
        let minAltitudeText = minAltitude.map { String(format: "%.3f", $0) } ?? "n/a"
        return [
            "episodes=\(episodeCount)",
            "fail=\(failureCount)",
            "trunc=\(truncatedCount)",
            "horizon=\(horizonLimitCount)",
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

    public mutating func add(_ other: RolloutHealth) {
        episodeCount += other.episodeCount
        doneCount += other.doneCount
        truncatedCount += other.truncatedCount
        failureCount += other.failureCount
        cancelledCount += other.cancelledCount
        horizonLimitCount += other.horizonLimitCount
        nonFiniteMetricCount += other.nonFiniteMetricCount
        rewardSum += other.rewardSum
        maxOmega = max(maxOmega, other.maxOmega)
        maxTilt = max(maxTilt, other.maxTilt)
        if let otherMinAltitude = other.minAltitude {
            minAltitude = min(minAltitude ?? otherMinAltitude, otherMinAltitude)
        }
    }

    public mutating func add(_ episode: RolloutEpisode) {
        addEpisodeHeader(
            done: episode.done,
            truncated: episode.truncated,
            failureReason: episode.failureReason,
            cancelled: episode.cancelled,
            terminalReason: episode.terminalReason,
            rewardSum: episode.rewardSum
        )
        for step in episode.steps {
            addStepMetrics(step)
        }
    }

    public mutating func addEpisodeSummary(
        done: Bool,
        truncated: Bool,
        failureReason: String?,
        cancelled: Bool = false,
        terminalReason: String?,
        rewardSum episodeRewardSum: Double,
        maxOmega episodeMaxOmega: Double,
        maxTilt episodeMaxTilt: Double,
        minAltitude episodeMinAltitude: Double?,
        nonFiniteMetricCount episodeNonFiniteMetricCount: Int = 0
    ) {
        addEpisodeHeader(
            done: done,
            truncated: truncated,
            failureReason: failureReason,
            cancelled: cancelled,
            terminalReason: terminalReason,
            rewardSum: episodeRewardSum
        )
        nonFiniteMetricCount += max(0, episodeNonFiniteMetricCount)
        addSummaryMetrics(
            maxOmega: episodeMaxOmega,
            maxTilt: episodeMaxTilt,
            minAltitude: episodeMinAltitude
        )
    }

    public func isAcceptable(
        relativeTo baseline: RolloutHealth,
        policy: RolloutHealthAcceptancePolicy = .conservative
    ) -> Bool {
        policy.accepts(candidate: self, relativeTo: baseline)
    }

    private mutating func addEpisodeHeader(
        done: Bool,
        truncated: Bool,
        failureReason: String?,
        cancelled: Bool,
        terminalReason: String?,
        rewardSum episodeRewardSum: Double
    ) {
        episodeCount += 1
        if done {
            doneCount += 1
        }
        if truncated {
            truncatedCount += 1
        }
        if failureReason != nil {
            failureCount += 1
        }
        if cancelled {
            cancelledCount += 1
        }
        if RolloutTerminalReason.isHorizonLimit(terminalReason) {
            horizonLimitCount += 1
        }
        if episodeRewardSum.isFinite {
            rewardSum += episodeRewardSum
        } else {
            nonFiniteMetricCount += 1
        }
    }

    private mutating func addSummaryMetrics(
        maxOmega episodeMaxOmega: Double,
        maxTilt episodeMaxTilt: Double,
        minAltitude episodeMinAltitude: Double?
    ) {
        if episodeMaxOmega.isFinite {
            maxOmega = max(maxOmega, episodeMaxOmega)
        } else {
            nonFiniteMetricCount += 1
        }

        if episodeMaxTilt.isFinite {
            maxTilt = max(maxTilt, episodeMaxTilt)
        } else {
            nonFiniteMetricCount += 1
        }

        if let episodeMinAltitude {
            if episodeMinAltitude.isFinite {
                minAltitude = min(minAltitude ?? episodeMinAltitude, episodeMinAltitude)
            } else {
                nonFiniteMetricCount += 1
            }
        }
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
