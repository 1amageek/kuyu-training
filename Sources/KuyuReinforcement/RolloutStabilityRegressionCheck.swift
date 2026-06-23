import Foundation
import KuyuTrainingContracts

public struct RolloutStabilityRegressionCheck: Sendable, Codable, Equatable {
    public let metricID: RolloutStabilityMetricID
    public let direction: RolloutStabilityRegressionDirection
    public let absoluteTolerance: Double
    public let relativeTolerance: Double
    public let rejectionReason: RolloutHealthRejectionReason

    public init(
        metricID: RolloutStabilityMetricID,
        direction: RolloutStabilityRegressionDirection,
        absoluteTolerance: Double,
        relativeTolerance: Double,
        rejectionReason: RolloutHealthRejectionReason
    ) throws {
        guard !metricID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RolloutStabilityRegressionContractError.emptyMetricID
        }
        guard absoluteTolerance.isFinite, absoluteTolerance >= 0,
              relativeTolerance.isFinite, relativeTolerance >= 0 else {
            throw RolloutStabilityRegressionContractError.invalidTolerance
        }
        self.metricID = metricID
        self.direction = direction
        self.absoluteTolerance = absoluteTolerance
        self.relativeTolerance = relativeTolerance
        self.rejectionReason = rejectionReason
    }

    init(
        uncheckedMetricID metricID: RolloutStabilityMetricID,
        direction: RolloutStabilityRegressionDirection,
        absoluteTolerance: Double,
        relativeTolerance: Double,
        rejectionReason: RolloutHealthRejectionReason
    ) {
        self.metricID = metricID
        self.direction = direction
        self.absoluteTolerance = absoluteTolerance
        self.relativeTolerance = relativeTolerance
        self.rejectionReason = rejectionReason
    }

    public func rejectionReason(
        candidate: RolloutHealth,
        relativeTo baseline: RolloutHealth
    ) -> RolloutHealthRejectionReason? {
        guard let baselineValue = baseline.stabilityMetricValue(metricID) else {
            return .stabilityMetricMissing
        }
        guard let candidateValue = candidate.stabilityMetricValue(metricID) else {
            return .stabilityMetricMissing
        }

        switch direction {
        case .upperBound:
            let limit = max(
                baselineValue + absoluteTolerance,
                baselineValue * (1 + relativeTolerance)
            )
            return candidateValue > limit ? rejectionReason : nil
        case .lowerBound:
            let limit = min(
                baselineValue - absoluteTolerance,
                baselineValue * (1 - relativeTolerance)
            )
            return candidateValue < limit ? rejectionReason : nil
        }
    }

    public func isDirectionallyImproved(
        candidate: RolloutHealth,
        relativeTo baseline: RolloutHealth
    ) -> Bool {
        guard let baselineValue = baseline.stabilityMetricValue(metricID),
              let candidateValue = candidate.stabilityMetricValue(metricID) else {
            return false
        }

        switch direction {
        case .upperBound:
            return candidateValue < baselineValue
        case .lowerBound:
            return candidateValue > baselineValue
        }
    }

    public func isMateriallyDirectionallyImproved(
        candidate: RolloutHealth,
        relativeTo baseline: RolloutHealth,
        toleranceScale: Double
    ) -> Bool {
        guard let baselineValue = baseline.stabilityMetricValue(metricID),
              let candidateValue = candidate.stabilityMetricValue(metricID) else {
            return false
        }
        let threshold = directionalImprovementThreshold(
            relativeTo: baselineValue,
            toleranceScale: toleranceScale
        )

        switch direction {
        case .upperBound:
            return candidateValue < baselineValue - threshold
        case .lowerBound:
            return candidateValue > baselineValue + threshold
        }
    }

    private func directionalImprovementThreshold(
        relativeTo baselineValue: Double,
        toleranceScale: Double
    ) -> Double {
        let scale = toleranceScale.isFinite ? max(0, toleranceScale) : 0
        return max(
            absoluteTolerance * scale,
            abs(baselineValue) * relativeTolerance * scale
        )
    }
}
