import Foundation
import KuyuTrainingContracts

public struct TrainingRunObservabilityProjection: Sendable {
    public enum ProjectionError: Error, Sendable, Equatable {
        case nonFiniteMetric(kind: TrainingMetricKind, iteration: Int)
        case emptyRunID
        case emptyScenarioID
    }

    public static let source = "training-run-artifact-projection"

    public init() {}

    public func artifact(
        manifest: LearningRunManifest,
        metrics: [TrainingMetricRecord],
        convergence: ConvergenceSummary,
        checkpointDecision: CheckpointDecision
    ) throws -> ConsciousUnconsciousObservabilityArtifact {
        guard !manifest.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectionError.emptyRunID
        }
        guard !manifest.suiteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectionError.emptyScenarioID
        }
        try validateMetrics(metrics)

        let iterations = projectedIterations(from: metrics)
        return ConsciousUnconsciousObservabilityArtifact(
            runID: manifest.runID,
            scenarioID: manifest.suiteID,
            seed: manifest.seedSet.first,
            timeStep: 1,
            descendingSnapshots: iterations.map { point in
                descendingSnapshot(
                    point: point,
                    manifest: manifest,
                    convergence: convergence
                )
            },
            upwardSummaries: iterations.map { point in
                upwardSummary(
                    point: point,
                    metrics: metrics,
                    convergence: convergence
                )
            },
            arbitrationDecisions: iterations.map { point in
                arbitrationDecision(
                    point: point,
                    metrics: metrics,
                    convergence: convergence,
                    checkpointDecision: checkpointDecision
                )
            }
        )
    }

    private func validateMetrics(_ metrics: [TrainingMetricRecord]) throws {
        for metric in metrics where !metric.value.isFinite {
            throw ProjectionError.nonFiniteMetric(kind: metric.kind, iteration: metric.iteration)
        }
    }

    private func projectedIterations(from metrics: [TrainingMetricRecord]) -> [ProjectedPoint] {
        let iterations = Set(metrics.map(\.iteration).filter { $0 >= 0 }).sorted()
        let orderedIterations = iterations.isEmpty ? [0] : iterations
        return orderedIterations.enumerated().map { offset, iteration in
            ProjectedPoint(iteration: iteration, timestamp: Double(offset))
        }
    }

    private func descendingSnapshot(
        point: ProjectedPoint,
        manifest: LearningRunManifest,
        convergence: ConvergenceSummary
    ) -> ConsciousUnconsciousObservabilityArtifact.DescendingSnapshot {
        ConsciousUnconsciousObservabilityArtifact.DescendingSnapshot(
            stepIndex: point.iteration,
            timestamp: point.timestamp,
            source: Self.source,
            goalID: manifest.policyID,
            priority: convergence.accepted ? 1 : 0,
            inhibition: terminalInhibition(manifest: manifest, convergence: convergence),
            contextHash: manifest.configHash
        )
    }

    private func upwardSummary(
        point: ProjectedPoint,
        metrics: [TrainingMetricRecord],
        convergence: ConvergenceSummary
    ) -> ConsciousUnconsciousObservabilityArtifact.UpwardSummary {
        let values = IterationMetricValues(iteration: point.iteration, metrics: metrics)
        let risk = max(
            values.unitValue(.failureRate) ?? convergence.failureRate,
            values.positivePresence(.safetyViolation),
            convergence.safetyRegressionDetected ? 1 : 0
        )
        let uncertainty = max(
            convergence.plateauDetected ? 1 : 0,
            convergence.overfitRiskDetected ? 1 : 0,
            values.hasScore ? 0 : 0.5
        )
        let salience = max(
            values.unitValue(.score) ?? 0,
            values.unitValue(.passRate) ?? convergence.passRate,
            unitClamped(convergence.rewardMovingAverage ?? 0)
        )
        let constraintPressure = max(
            risk,
            values.unitValue(.loss) ?? 0,
            values.unitValue(.validationLoss) ?? 0
        )
        let recoveryState = convergence.accepted
            ? 1
            : max(0, min(1, 1 - max(risk, uncertainty)))

        return ConsciousUnconsciousObservabilityArtifact.UpwardSummary(
            stepIndex: point.iteration,
            timestamp: point.timestamp,
            channels: [
                .init(name: "salience", stableIndex: 0, value: salience),
                .init(name: "risk", stableIndex: 1, value: unitClamped(risk)),
                .init(name: "uncertainty", stableIndex: 2, value: unitClamped(uncertainty)),
                .init(name: "constraintPressure", stableIndex: 3, value: unitClamped(constraintPressure)),
                .init(name: "recoveryState", stableIndex: 4, value: unitClamped(recoveryState)),
            ]
        )
    }

    private func arbitrationDecision(
        point: ProjectedPoint,
        metrics: [TrainingMetricRecord],
        convergence: ConvergenceSummary,
        checkpointDecision: CheckpointDecision
    ) -> ConsciousUnconsciousObservabilityArtifact.ArbitrationDecision {
        let values = IterationMetricValues(iteration: point.iteration, metrics: metrics)
        let risk = max(
            values.unitValue(.failureRate) ?? convergence.failureRate,
            values.positivePresence(.safetyViolation),
            convergence.safetyRegressionDetected ? 1 : 0
        )
        let score = values.unitValue(.score) ?? convergence.passRate
        let finalDrive = checkpointDecision.state == .accepted || checkpointDecision.state == .staged ? 1.0 : 0.0
        let preempted = convergence.safetyRegressionDetected
            || checkpointDecision.state == .rejected
            || checkpointDecision.state == .failed
            || checkpointDecision.state == .skipped

        return ConsciousUnconsciousObservabilityArtifact.ArbitrationDecision(
            stepIndex: point.iteration,
            timestamp: point.timestamp,
            coreDriveMagnitude: max(0.0, score),
            reflexCorrectionMagnitude: max(0.0, risk),
            finalDriveMagnitude: finalDrive,
            reflexPreemptedDescendingBias: preempted,
            reason: "checkpoint-\(checkpointDecision.state.rawValue): \(checkpointDecision.reason)"
        )
    }

    private func terminalInhibition(
        manifest: LearningRunManifest,
        convergence: ConvergenceSummary
    ) -> Double {
        if convergence.safetyRegressionDetected {
            return 1
        }
        switch manifest.terminalState {
        case .failed, .cancelled, .rejected:
            return 1
        case .running:
            return 0.5
        case .completed:
            return 0
        }
    }
}

private struct ProjectedPoint: Sendable, Equatable {
    let iteration: Int
    let timestamp: Double
}

private struct IterationMetricValues: Sendable {
    private let values: [TrainingMetricKind: Double]

    init(iteration: Int, metrics: [TrainingMetricRecord]) {
        var observed: [TrainingMetricKind: Double] = [:]
        for metric in metrics where metric.iteration == iteration {
            observed[metric.kind] = metric.value
        }
        values = observed
    }

    var hasScore: Bool {
        values[.score] != nil
    }

    func unitValue(_ kind: TrainingMetricKind) -> Double? {
        values[kind].map(unitClamped)
    }

    func positivePresence(_ kind: TrainingMetricKind) -> Double {
        guard let value = values[kind] else {
            return 0
        }
        return value > 0 ? 1 : 0
    }
}

private func unitClamped(_ value: Double) -> Double {
    max(0, min(1, value))
}
