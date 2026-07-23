import Foundation

public struct ConsciousUnconsciousObservabilityArtifactValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable {
        case unsupportedSchemaVersion(Int)
        case emptyRunID
        case emptyScenarioID
        case invalidTimeStep(Double)
        case invalidPositive(field: String, value: Double)
        case emptyDescendingSnapshots
        case emptyUpwardSummaries
        case emptyArbitrationDecisions
        case invalidStepIndex(kind: String, stepIndex: Int)
        case nonMonotonicTimestamp(kind: String, previous: Double, current: Double)
        case nonFinite(field: String)
        case invalidUnitRange(field: String, value: Double)
        case emptySource
        case emptySummaryChannels(stepIndex: Int)
        case duplicateSummaryChannel(stepIndex: Int, name: String)
        case missingSummaryChannel(stepIndex: Int, name: String)
        case summaryChannelIndexMismatch(name: String, expected: Int, actual: Int)
        case emptyArbitrationReason(stepIndex: Int)
        case emptyLatencyPath(stepIndex: Int)
        case emptyLatencyReason(stepIndex: Int)
        case latencyBudgetNotExceeded(stepIndex: Int, budget: Double, observed: Double)
        case timelineCountMismatch(kind: String, expected: Int, actual: Int)
        case timelinePointMismatch(
            kind: String,
            index: Int,
            expectedStepIndex: Int,
            actualStepIndex: Int,
            expectedTimestamp: Double,
            actualTimestamp: Double
        )
        case nonIncreasingTimelinePoint(
            kind: String,
            index: Int,
            previousStepIndex: Int,
            currentStepIndex: Int,
            previousTimestamp: Double,
            currentTimestamp: Double
        )
        case latencyTimelinePointMissing(stepIndex: Int, timestamp: Double)
    }

    public static let requiredSummaryChannels: [String: Int] = [
        "salience": 0,
        "risk": 1,
        "uncertainty": 2,
        "constraintPressure": 3,
        "recoveryState": 4,
    ]

    public init() {}

    public func validate(_ artifact: ConsciousUnconsciousObservabilityArtifact) throws {
        guard artifact.schemaVersion == ConsciousUnconsciousObservabilityArtifact.currentSchemaVersion else {
            throw ValidationError.unsupportedSchemaVersion(artifact.schemaVersion)
        }
        guard !artifact.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyRunID
        }
        guard !artifact.scenarioID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyScenarioID
        }
        try validatePositiveFinite(artifact.timeStep, field: "timeStep")
        guard !artifact.descendingSnapshots.isEmpty else {
            throw ValidationError.emptyDescendingSnapshots
        }
        guard !artifact.upwardSummaries.isEmpty else {
            throw ValidationError.emptyUpwardSummaries
        }
        guard !artifact.arbitrationDecisions.isEmpty else {
            throw ValidationError.emptyArbitrationDecisions
        }
        try validateDescendingSnapshots(artifact.descendingSnapshots)
        try validateUpwardSummaries(artifact.upwardSummaries)
        try validateArbitrationDecisions(artifact.arbitrationDecisions)
        try validateLatencyBudgetViolations(artifact.latencyBudgetViolations)
        try validateAlignedTimelines(artifact)
    }

    private struct TimelinePoint: Equatable {
        let stepIndex: Int
        let timestamp: Double
    }

    private func validateDescendingSnapshots(
        _ snapshots: [ConsciousUnconsciousObservabilityArtifact.DescendingSnapshot]
    ) throws {
        var previousTimestamp: Double?
        for snapshot in snapshots {
            try validateTimelinePoint(
                kind: "descending",
                stepIndex: snapshot.stepIndex,
                timestamp: snapshot.timestamp,
                previousTimestamp: &previousTimestamp
            )
            guard !snapshot.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.emptySource
            }
            try validateUnitRange(snapshot.priority, field: "descending.priority")
            try validateUnitRange(snapshot.inhibition, field: "descending.inhibition")
        }
    }

    private func validateUpwardSummaries(
        _ summaries: [ConsciousUnconsciousObservabilityArtifact.UpwardSummary]
    ) throws {
        var previousTimestamp: Double?
        for summary in summaries {
            try validateTimelinePoint(
                kind: "upwardSummary",
                stepIndex: summary.stepIndex,
                timestamp: summary.timestamp,
                previousTimestamp: &previousTimestamp
            )
            guard !summary.channels.isEmpty else {
                throw ValidationError.emptySummaryChannels(stepIndex: summary.stepIndex)
            }
            var channelsByName: [String: ConsciousUnconsciousObservabilityArtifact.ScalarChannel] = [:]
            for channel in summary.channels {
                let name = channel.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    throw ValidationError.missingSummaryChannel(stepIndex: summary.stepIndex, name: "")
                }
                guard channelsByName[name] == nil else {
                    throw ValidationError.duplicateSummaryChannel(stepIndex: summary.stepIndex, name: name)
                }
                try validateUnitRange(channel.value, field: "upwardSummary.\(name)")
                channelsByName[name] = channel
            }
            for (name, stableIndex) in Self.requiredSummaryChannels {
                guard let channel = channelsByName[name] else {
                    throw ValidationError.missingSummaryChannel(stepIndex: summary.stepIndex, name: name)
                }
                guard channel.stableIndex == stableIndex else {
                    throw ValidationError.summaryChannelIndexMismatch(
                        name: name,
                        expected: stableIndex,
                        actual: channel.stableIndex
                    )
                }
            }
        }
    }

    private func validateArbitrationDecisions(
        _ decisions: [ConsciousUnconsciousObservabilityArtifact.ArbitrationDecision]
    ) throws {
        var previousTimestamp: Double?
        for decision in decisions {
            try validateTimelinePoint(
                kind: "arbitration",
                stepIndex: decision.stepIndex,
                timestamp: decision.timestamp,
                previousTimestamp: &previousTimestamp
            )
            try validateNonNegativeFinite(decision.coreDriveMagnitude, field: "arbitration.coreDriveMagnitude")
            try validateNonNegativeFinite(
                decision.reflexCorrectionMagnitude,
                field: "arbitration.reflexCorrectionMagnitude"
            )
            try validateNonNegativeFinite(decision.finalDriveMagnitude, field: "arbitration.finalDriveMagnitude")
            guard !decision.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.emptyArbitrationReason(stepIndex: decision.stepIndex)
            }
        }
    }

    private func validateLatencyBudgetViolations(
        _ violations: [ConsciousUnconsciousObservabilityArtifact.LatencyBudgetViolation]
    ) throws {
        var previousTimestamp: Double?
        for violation in violations {
            try validateTimelinePoint(
                kind: "latency",
                stepIndex: violation.stepIndex,
                timestamp: violation.timestamp,
                previousTimestamp: &previousTimestamp
            )
            guard !violation.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.emptyLatencyPath(stepIndex: violation.stepIndex)
            }
            guard !violation.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.emptyLatencyReason(stepIndex: violation.stepIndex)
            }
            try validatePositiveFinite(violation.budgetMilliseconds, field: "latency.budgetMilliseconds")
            try validatePositiveFinite(violation.observedMilliseconds, field: "latency.observedMilliseconds")
            guard violation.observedMilliseconds > violation.budgetMilliseconds else {
                throw ValidationError.latencyBudgetNotExceeded(
                    stepIndex: violation.stepIndex,
                    budget: violation.budgetMilliseconds,
                    observed: violation.observedMilliseconds
                )
            }
        }
    }

    private func validateAlignedTimelines(_ artifact: ConsciousUnconsciousObservabilityArtifact) throws {
        let expected = artifact.descendingSnapshots.map {
            TimelinePoint(stepIndex: $0.stepIndex, timestamp: $0.timestamp)
        }
        try validateStrictTimeline(expected, kind: "descending")
        try validateTimeline(
            artifact.upwardSummaries.map { TimelinePoint(stepIndex: $0.stepIndex, timestamp: $0.timestamp) },
            kind: "upwardSummary",
            expected: expected
        )
        try validateTimeline(
            artifact.arbitrationDecisions.map { TimelinePoint(stepIndex: $0.stepIndex, timestamp: $0.timestamp) },
            kind: "arbitration",
            expected: expected
        )
        for violation in artifact.latencyBudgetViolations {
            let point = TimelinePoint(stepIndex: violation.stepIndex, timestamp: violation.timestamp)
            guard expected.contains(point) else {
                throw ValidationError.latencyTimelinePointMissing(
                    stepIndex: violation.stepIndex,
                    timestamp: violation.timestamp
                )
            }
        }
    }

    private func validateStrictTimeline(_ points: [TimelinePoint], kind: String) throws {
        for index in points.indices.dropFirst() {
            let previous = points[index - 1]
            let current = points[index]
            guard current.stepIndex > previous.stepIndex, current.timestamp > previous.timestamp else {
                throw ValidationError.nonIncreasingTimelinePoint(
                    kind: kind,
                    index: index,
                    previousStepIndex: previous.stepIndex,
                    currentStepIndex: current.stepIndex,
                    previousTimestamp: previous.timestamp,
                    currentTimestamp: current.timestamp
                )
            }
        }
    }

    private func validateTimeline(
        _ actual: [TimelinePoint],
        kind: String,
        expected: [TimelinePoint]
    ) throws {
        guard actual.count == expected.count else {
            throw ValidationError.timelineCountMismatch(
                kind: kind,
                expected: expected.count,
                actual: actual.count
            )
        }
        for (index, expectedPoint) in expected.enumerated() {
            let actualPoint = actual[index]
            guard actualPoint == expectedPoint else {
                throw ValidationError.timelinePointMismatch(
                    kind: kind,
                    index: index,
                    expectedStepIndex: expectedPoint.stepIndex,
                    actualStepIndex: actualPoint.stepIndex,
                    expectedTimestamp: expectedPoint.timestamp,
                    actualTimestamp: actualPoint.timestamp
                )
            }
        }
    }

    private func validateTimelinePoint(
        kind: String,
        stepIndex: Int,
        timestamp: Double,
        previousTimestamp: inout Double?
    ) throws {
        guard stepIndex >= 0 else {
            throw ValidationError.invalidStepIndex(kind: kind, stepIndex: stepIndex)
        }
        try validateNonNegativeFinite(timestamp, field: "\(kind).timestamp")
        if let previousTimestamp, timestamp < previousTimestamp {
            throw ValidationError.nonMonotonicTimestamp(
                kind: kind,
                previous: previousTimestamp,
                current: timestamp
            )
        }
        previousTimestamp = timestamp
    }

    private func validateUnitRange(_ value: Double, field: String) throws {
        guard value.isFinite else {
            throw ValidationError.nonFinite(field: field)
        }
        guard value >= 0, value <= 1 else {
            throw ValidationError.invalidUnitRange(field: field, value: value)
        }
    }

    private func validatePositiveFinite(_ value: Double, field: String) throws {
        guard value.isFinite else {
            throw ValidationError.nonFinite(field: field)
        }
        guard value > 0 else {
            if field == "timeStep" {
                throw ValidationError.invalidTimeStep(value)
            }
            throw ValidationError.invalidPositive(field: field, value: value)
        }
    }

    private func validateNonNegativeFinite(_ value: Double, field: String) throws {
        guard value.isFinite else {
            throw ValidationError.nonFinite(field: field)
        }
        guard value >= 0 else {
            throw ValidationError.invalidUnitRange(field: field, value: value)
        }
    }
}
