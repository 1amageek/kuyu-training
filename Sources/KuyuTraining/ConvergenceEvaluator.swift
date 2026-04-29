import Foundation

public struct ConvergenceEvaluator: Sendable {
    public struct Config: Sendable, Codable, Equatable {
        public let windowSize: Int
        public let minDelta: Double

        public init(windowSize: Int = 3, minDelta: Double = 0.01) {
            self.windowSize = max(1, windowSize)
            self.minDelta = minDelta
        }
    }

    public let config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    public func evaluate(
        runID: String,
        metrics: [TrainingMetricRecord],
        bestCheckpointID: String?
    ) -> ConvergenceSummary {
        guard metrics.allSatisfy({ $0.value.isFinite }) else {
            return summary(
                runID: runID,
                metrics: metrics,
                accepted: false,
                reason: "non-finite-metric",
                bestCheckpointID: bestCheckpointID,
                safetyRegression: false,
                plateau: false,
                overfitRisk: false
            )
        }

        let safetyRegression = hasSafetyRegression(metrics)
        let overfitRisk = hasOverfitRisk(metrics)
        let improved = hasLossImprovement(metrics) || hasScoreImprovement(metrics) || hasRewardImprovement(metrics) || hasInsufficientHistory(metrics)
        let plateau = !improved && hasEnoughHistory(metrics)

        if safetyRegression {
            return summary(
                runID: runID,
                metrics: metrics,
                accepted: false,
                reason: "safety-regression",
                bestCheckpointID: bestCheckpointID,
                safetyRegression: true,
                plateau: plateau,
                overfitRisk: overfitRisk
            )
        }

        if overfitRisk {
            return summary(
                runID: runID,
                metrics: metrics,
                accepted: false,
                reason: "overfit-risk",
                bestCheckpointID: bestCheckpointID,
                safetyRegression: false,
                plateau: plateau,
                overfitRisk: true
            )
        }

        if plateau {
            return summary(
                runID: runID,
                metrics: metrics,
                accepted: false,
                reason: "plateau",
                bestCheckpointID: bestCheckpointID,
                safetyRegression: false,
                plateau: true,
                overfitRisk: false
            )
        }

        return summary(
            runID: runID,
            metrics: metrics,
            accepted: true,
            reason: "accepted",
            bestCheckpointID: bestCheckpointID,
            safetyRegression: false,
            plateau: false,
            overfitRisk: false
        )
    }

    private func summary(
        runID: String,
        metrics: [TrainingMetricRecord],
        accepted: Bool,
        reason: String,
        bestCheckpointID: String?,
        safetyRegression: Bool,
        plateau: Bool,
        overfitRisk: Bool
    ) -> ConvergenceSummary {
        ConvergenceSummary(
            runID: runID,
            accepted: accepted,
            reason: reason,
            bestCheckpointID: bestCheckpointID,
            finalTrainingLoss: lastValue(.loss, in: metrics),
            finalValidationLoss: lastValue(.validationLoss, in: metrics),
            rewardMovingAverage: movingAverage(values(for: .rewardAverage, in: metrics).suffix(config.windowSize)),
            passRate: lastValue(.passRate, in: metrics) ?? 0,
            failureRate: lastValue(.failureRate, in: metrics) ?? 0,
            safetyRegressionDetected: safetyRegression,
            plateauDetected: plateau,
            overfitRiskDetected: overfitRisk
        )
    }

    private func hasSafetyRegression(_ metrics: [TrainingMetricRecord]) -> Bool {
        let safety = values(for: .safetyViolation, in: metrics)
        let failure = values(for: .failureRate, in: metrics)
        return increased(safety) || increased(failure)
    }

    private func hasOverfitRisk(_ metrics: [TrainingMetricRecord]) -> Bool {
        let losses = values(for: .loss, in: metrics)
        let validations = values(for: .validationLoss, in: metrics)
        guard hasWindow(losses), hasWindow(validations) else { return false }
        return decreased(losses) && increased(validations)
    }

    private func hasLossImprovement(_ metrics: [TrainingMetricRecord]) -> Bool {
        let losses = values(for: .loss, in: metrics)
        guard hasWindow(losses) else { return false }
        return decreased(losses)
    }

    private func hasScoreImprovement(_ metrics: [TrainingMetricRecord]) -> Bool {
        let scores = values(for: .score, in: metrics)
        guard hasWindow(scores) else { return false }
        return increased(scores)
    }

    private func hasRewardImprovement(_ metrics: [TrainingMetricRecord]) -> Bool {
        let rewards = values(for: .rewardAverage, in: metrics)
        guard hasWindow(rewards) else { return false }
        return increased(rewards)
    }

    private func hasInsufficientHistory(_ metrics: [TrainingMetricRecord]) -> Bool {
        !hasEnoughHistory(metrics)
    }

    private func hasEnoughHistory(_ metrics: [TrainingMetricRecord]) -> Bool {
        hasWindow(values(for: .loss, in: metrics))
            || hasWindow(values(for: .score, in: metrics))
            || hasWindow(values(for: .rewardAverage, in: metrics))
    }

    private func hasWindow(_ values: [Double]) -> Bool {
        values.count >= config.windowSize * 2
    }

    private func decreased(_ values: [Double]) -> Bool {
        guard hasWindow(values) else { return false }
        let previous = movingAverage(values.dropLast(config.windowSize).suffix(config.windowSize))
        let current = movingAverage(values.suffix(config.windowSize))
        guard let previous, let current else { return false }
        return current <= previous - config.minDelta
    }

    private func increased(_ values: [Double]) -> Bool {
        guard hasWindow(values) else { return false }
        let previous = movingAverage(values.dropLast(config.windowSize).suffix(config.windowSize))
        let current = movingAverage(values.suffix(config.windowSize))
        guard let previous, let current else { return false }
        return current >= previous + config.minDelta
    }

    private func values(for kind: TrainingMetricKind, in metrics: [TrainingMetricRecord]) -> [Double] {
        metrics
            .filter { $0.kind == kind }
            .sorted { lhs, rhs in
                if lhs.iteration != rhs.iteration { return lhs.iteration < rhs.iteration }
                return (lhs.step ?? 0) < (rhs.step ?? 0)
            }
            .map(\.value)
    }

    private func lastValue(_ kind: TrainingMetricKind, in metrics: [TrainingMetricRecord]) -> Double? {
        values(for: kind, in: metrics).last
    }

    private func movingAverage<S: Sequence>(_ values: S) -> Double? where S.Element == Double {
        let array = Array(values)
        guard !array.isEmpty else { return nil }
        return array.reduce(0, +) / Double(array.count)
    }
}
