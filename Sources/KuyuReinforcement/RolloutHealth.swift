import Foundation
import KuyuTrainingContracts

public struct RolloutHealth: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Sendable, Equatable {
        case negativeCounter(field: String, value: Int)
        case counterExceedsEpisodeCount(field: String, value: Int, episodeCount: Int)
        case horizonCountExceedsTruncationCount(horizon: Int, truncated: Int)
        case invalidFailureReason(String)
        case invalidFailureReasonCount(reason: String, count: Int)
        case failureReasonCountMismatch(expected: Int, actual: Int)
        case nonFiniteMetric(String)
        case negativeMagnitude(field: String, value: Double)
    }

    public private(set) var episodeCount: Int
    public private(set) var doneCount: Int
    public private(set) var truncatedCount: Int
    public private(set) var failureCount: Int
    public private(set) var cancelledCount: Int
    public private(set) var horizonLimitCount: Int
    public private(set) var terminalStepObservationCount: Int
    public private(set) var terminalStepSum: Int
    public private(set) var nonFiniteMetricCount: Int
    public private(set) var rewardSum: Double
    public private(set) var maxOmega: Double
    public private(set) var maxTilt: Double
    public private(set) var minAltitude: Double?
    public private(set) var failureReasonCounts: [String: Int]
    public private(set) var stabilityMetrics: [String: RolloutStabilityMetricSummary]
    public private(set) var stabilityMetricContractViolations: [RolloutStabilityMetricContractViolation]

    public init() {
        episodeCount = 0
        doneCount = 0
        truncatedCount = 0
        failureCount = 0
        cancelledCount = 0
        horizonLimitCount = 0
        terminalStepObservationCount = 0
        terminalStepSum = 0
        nonFiniteMetricCount = 0
        rewardSum = 0
        maxOmega = 0
        maxTilt = 0
        minAltitude = nil
        failureReasonCounts = [:]
        stabilityMetrics = [:]
        stabilityMetricContractViolations = []
    }

    public var failureRate: Double {
        Double(failureCount) / Double(max(episodeCount, 1))
    }

    public var rewardAverage: Double {
        rewardSum / Double(max(episodeCount, 1))
    }

    public var terminalStepAverage: Double {
        Double(terminalStepSum) / Double(max(terminalStepObservationCount, 1))
    }

    public var nonHorizonTruncationCount: Int {
        max(0, truncatedCount - horizonLimitCount)
    }

    public var trainingDecisionContractRejectionReasons: [RolloutHealthRejectionReason] {
        var reasons: [RolloutHealthRejectionReason] = []
        if nonFiniteMetricCount > 0 {
            reasons.append(.nonFiniteMetric)
        }
        if !stabilityMetricContractViolations.isEmpty {
            reasons.append(.stabilityMetricContractViolation)
        }
        return reasons
    }

    public var isValidForTrainingDecision: Bool {
        trainingDecisionContractRejectionReasons.isEmpty
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
            "stepAvg=\(String(format: "%.1f", terminalStepAverage))",
            "omega=\(String(format: "%.3f", maxOmega))",
            "tilt=\(String(format: "%.3f", maxTilt))",
            "minZ=\(minAltitudeText)",
            "failureReasons=\(failureReasonSummary)",
            "nonFinite=\(nonFiniteMetricCount)",
        ].joined(separator: " ")
    }

    public func failureReasonCount(_ reason: String) -> Int {
        let key = Self.sanitizedFailureReason(reason)
        guard !key.isEmpty else { return 0 }
        return failureReasonCounts[key] ?? 0
    }

    public func containsFailureReason(in reasons: Set<String>) -> Bool {
        failureReasonCounts.keys.contains { reasons.contains($0) }
    }

    public func containsFailureReason(matching fragments: Set<String>) -> Bool {
        let sanitizedFragments = fragments
            .map(Self.sanitizedFailureReason)
            .filter { !$0.isEmpty }
        guard !sanitizedFragments.isEmpty else { return false }
        return failureReasonCounts.keys.contains { reason in
            sanitizedFragments.contains { fragment in
                reason.contains(fragment)
            }
        }
    }

    public mutating func add(_ other: RolloutHealth) {
        episodeCount += other.episodeCount
        doneCount += other.doneCount
        truncatedCount += other.truncatedCount
        failureCount += other.failureCount
        cancelledCount += other.cancelledCount
        horizonLimitCount += other.horizonLimitCount
        terminalStepObservationCount += other.terminalStepObservationCount
        terminalStepSum += other.terminalStepSum
        nonFiniteMetricCount += other.nonFiniteMetricCount
        rewardSum += other.rewardSum
        maxOmega = max(maxOmega, other.maxOmega)
        maxTilt = max(maxTilt, other.maxTilt)
        if let otherMinAltitude = other.minAltitude {
            minAltitude = min(minAltitude ?? otherMinAltitude, otherMinAltitude)
        }
        for (reason, count) in other.failureReasonCounts {
            failureReasonCounts[reason, default: 0] += count
        }
        stabilityMetricContractViolations.append(contentsOf: other.stabilityMetricContractViolations)
        for metric in other.stabilityMetrics.values {
            recordStabilityMetric(
                id: metric.id,
                value: metric.value,
                aggregation: metric.aggregation
            )
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
        terminalStepCount: Int? = nil,
        nonFiniteMetricCount episodeNonFiniteMetricCount: Int = 0,
        stabilityMetrics episodeStabilityMetrics: [RolloutStabilityMetricSummary] = []
    ) {
        addEpisodeHeader(
            done: done,
            truncated: truncated,
            failureReason: failureReason,
            cancelled: cancelled,
            terminalReason: terminalReason,
            rewardSum: episodeRewardSum,
            terminalStepCount: terminalStepCount
        )
        nonFiniteMetricCount += max(0, episodeNonFiniteMetricCount)
        addSummaryMetrics(
            maxOmega: episodeMaxOmega,
            maxTilt: episodeMaxTilt,
            minAltitude: episodeMinAltitude
        )
        for metric in episodeStabilityMetrics {
            recordStabilityMetric(
                id: metric.id,
                value: metric.value,
                aggregation: metric.aggregation
            )
        }
    }

    public func isAcceptable(
        relativeTo baseline: RolloutHealth,
        policy: RolloutHealthAcceptancePolicy = .conservative
    ) -> Bool {
        policy.accepts(candidate: self, relativeTo: baseline)
    }

    public func stabilityMetricValue(_ id: RolloutStabilityMetricID) -> Double? {
        stabilityMetrics[id.rawValue]?.value
    }

    public mutating func recordStabilityMetric(
        id: RolloutStabilityMetricID,
        value: Double,
        aggregation: RolloutStabilityMetricAggregation
    ) {
        guard value.isFinite else {
            nonFiniteMetricCount += 1
            return
        }
        guard !id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            stabilityMetricContractViolations.append(RolloutStabilityMetricContractViolation(
                metricID: id,
                reason: .emptyMetricID
            ))
            return
        }
        if let existing = stabilityMetrics[id.rawValue],
           existing.aggregation != aggregation {
            stabilityMetricContractViolations.append(RolloutStabilityMetricContractViolation(
                metricID: id,
                reason: .aggregationMismatch
            ))
            return
        }
        let existingValue = stabilityMetrics[id.rawValue]?.value ?? value
        let mergedValue: Double
        switch aggregation {
        case .maximum:
            mergedValue = max(existingValue, value)
        case .minimum:
            mergedValue = min(existingValue, value)
        }
        stabilityMetrics[id.rawValue] = RolloutStabilityMetricSummary(
            id: id,
            aggregation: aggregation,
            value: mergedValue
        )
    }

    private mutating func addEpisodeHeader(
        done: Bool,
        truncated: Bool,
        failureReason: String?,
        cancelled: Bool,
        terminalReason: String?,
        rewardSum episodeRewardSum: Double,
        terminalStepCount: Int?
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
        if let failureReason {
            let key = Self.sanitizedFailureReason(failureReason)
            if !key.isEmpty {
                failureReasonCounts[key, default: 0] += 1
            }
        }
        if cancelled {
            cancelledCount += 1
        }
        if RolloutTerminalReason.isHorizonLimit(terminalReason) {
            horizonLimitCount += 1
        }
        if let terminalStepCount {
            terminalStepObservationCount += 1
            terminalStepSum += max(0, terminalStepCount)
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
            recordStabilityMetric(
                id: .maximumAngularRate,
                value: episodeMaxOmega,
                aggregation: .maximum
            )
        } else {
            nonFiniteMetricCount += 1
        }

        if episodeMaxTilt.isFinite {
            maxTilt = max(maxTilt, episodeMaxTilt)
            recordStabilityMetric(
                id: .maximumAttitudeDeviation,
                value: episodeMaxTilt,
                aggregation: .maximum
            )
        } else {
            nonFiniteMetricCount += 1
        }

        if let episodeMinAltitude {
            if episodeMinAltitude.isFinite {
                minAltitude = min(minAltitude ?? episodeMinAltitude, episodeMinAltitude)
                recordStabilityMetric(
                    id: .minimumRootAltitude,
                    value: episodeMinAltitude,
                    aggregation: .minimum
                )
            } else {
                nonFiniteMetricCount += 1
            }
        }
    }

    private var failureReasonSummary: String {
        guard !failureReasonCounts.isEmpty else { return "none" }
        return failureReasonCounts
            .sorted { first, second in
                if first.value == second.value {
                    return first.key < second.key
                }
                return first.value > second.value
            }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
    }

    private static func sanitizedFailureReason(_ reason: String) -> String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case episodeCount
        case doneCount
        case truncatedCount
        case failureCount
        case cancelledCount
        case horizonLimitCount
        case terminalStepObservationCount
        case terminalStepSum
        case nonFiniteMetricCount
        case rewardSum
        case maxOmega
        case maxTilt
        case minAltitude
        case failureReasonCounts
        case stabilityMetrics
        case stabilityMetricContractViolations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        episodeCount = try container.decode(Int.self, forKey: .episodeCount)
        doneCount = try container.decode(Int.self, forKey: .doneCount)
        truncatedCount = try container.decode(Int.self, forKey: .truncatedCount)
        failureCount = try container.decode(Int.self, forKey: .failureCount)
        cancelledCount = try container.decode(Int.self, forKey: .cancelledCount)
        horizonLimitCount = try container.decode(Int.self, forKey: .horizonLimitCount)
        terminalStepObservationCount = try container.decodeIfPresent(
            Int.self,
            forKey: .terminalStepObservationCount
        ) ?? 0
        terminalStepSum = try container.decodeIfPresent(Int.self, forKey: .terminalStepSum) ?? 0
        nonFiniteMetricCount = try container.decode(Int.self, forKey: .nonFiniteMetricCount)
        rewardSum = try container.decode(Double.self, forKey: .rewardSum)
        maxOmega = try container.decode(Double.self, forKey: .maxOmega)
        maxTilt = try container.decode(Double.self, forKey: .maxTilt)
        minAltitude = try container.decodeIfPresent(Double.self, forKey: .minAltitude)
        failureReasonCounts = try container.decodeIfPresent(
            [String: Int].self,
            forKey: .failureReasonCounts
        ) ?? [:]
        stabilityMetrics = try container.decode(
            [String: RolloutStabilityMetricSummary].self,
            forKey: .stabilityMetrics
        )
        stabilityMetricContractViolations = try container.decode(
            [RolloutStabilityMetricContractViolation].self,
            forKey: .stabilityMetricContractViolations
        )
        try validateDecodedState()
    }

    private func validateDecodedState() throws {
        for (field, value) in [
            ("episodeCount", episodeCount),
            ("doneCount", doneCount),
            ("truncatedCount", truncatedCount),
            ("failureCount", failureCount),
            ("cancelledCount", cancelledCount),
            ("horizonLimitCount", horizonLimitCount),
            ("terminalStepObservationCount", terminalStepObservationCount),
            ("terminalStepSum", terminalStepSum),
            ("nonFiniteMetricCount", nonFiniteMetricCount),
        ] where value < 0 {
            throw ValidationError.negativeCounter(field: field, value: value)
        }
        for (field, value) in [
            ("doneCount", doneCount),
            ("truncatedCount", truncatedCount),
            ("failureCount", failureCount),
            ("cancelledCount", cancelledCount),
            ("terminalStepObservationCount", terminalStepObservationCount),
        ] where value > episodeCount {
            throw ValidationError.counterExceedsEpisodeCount(
                field: field,
                value: value,
                episodeCount: episodeCount
            )
        }
        guard horizonLimitCount <= truncatedCount else {
            throw ValidationError.horizonCountExceedsTruncationCount(
                horizon: horizonLimitCount,
                truncated: truncatedCount
            )
        }
        var recordedFailureCount = 0
        for (reason, count) in failureReasonCounts {
            let sanitized = Self.sanitizedFailureReason(reason)
            guard !sanitized.isEmpty, sanitized == reason else {
                throw ValidationError.invalidFailureReason(reason)
            }
            guard count > 0 else {
                throw ValidationError.invalidFailureReasonCount(
                    reason: reason,
                    count: count
                )
            }
            let addition = recordedFailureCount.addingReportingOverflow(count)
            guard !addition.overflow else {
                throw ValidationError.invalidFailureReasonCount(
                    reason: reason,
                    count: count
                )
            }
            recordedFailureCount = addition.partialValue
        }
        guard recordedFailureCount == failureCount else {
            throw ValidationError.failureReasonCountMismatch(
                expected: failureCount,
                actual: recordedFailureCount
            )
        }
        for (field, value) in [
            ("rewardSum", rewardSum),
            ("maxOmega", maxOmega),
            ("maxTilt", maxTilt),
        ] where !value.isFinite {
            throw ValidationError.nonFiniteMetric(field)
        }
        if let minAltitude, !minAltitude.isFinite {
            throw ValidationError.nonFiniteMetric("minAltitude")
        }
        for (field, value) in [("maxOmega", maxOmega), ("maxTilt", maxTilt)]
        where value < 0 {
            throw ValidationError.negativeMagnitude(field: field, value: value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(episodeCount, forKey: .episodeCount)
        try container.encode(doneCount, forKey: .doneCount)
        try container.encode(truncatedCount, forKey: .truncatedCount)
        try container.encode(failureCount, forKey: .failureCount)
        try container.encode(cancelledCount, forKey: .cancelledCount)
        try container.encode(horizonLimitCount, forKey: .horizonLimitCount)
        try container.encode(terminalStepObservationCount, forKey: .terminalStepObservationCount)
        try container.encode(terminalStepSum, forKey: .terminalStepSum)
        try container.encode(nonFiniteMetricCount, forKey: .nonFiniteMetricCount)
        try container.encode(rewardSum, forKey: .rewardSum)
        try container.encode(maxOmega, forKey: .maxOmega)
        try container.encode(maxTilt, forKey: .maxTilt)
        try container.encodeIfPresent(minAltitude, forKey: .minAltitude)
        try container.encode(failureReasonCounts, forKey: .failureReasonCounts)
        try container.encode(stabilityMetrics, forKey: .stabilityMetrics)
        try container.encode(
            stabilityMetricContractViolations,
            forKey: .stabilityMetricContractViolations
        )
    }
}
