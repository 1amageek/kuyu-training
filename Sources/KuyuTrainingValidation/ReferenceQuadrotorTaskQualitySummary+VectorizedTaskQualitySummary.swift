import KuyuScenarios
import KuyuReinforcement

public extension VectorizedTaskQualitySummary {
    init(
        referenceQuadrotor summary: ReferenceQuadrotorTaskQualitySummary,
        scenarioSuiteID: String
    ) throws {
        var metrics: [String: Double] = [:]
        Self.assign(summary.targetZ, to: "targetZ", in: &metrics)
        Self.assign(summary.tolerance, to: "tolerance", in: &metrics)
        Self.assign(summary.warmupTime, to: "warmupTime", in: &metrics)
        Self.assign(summary.requiredHoldTime, to: "requiredHoldTime", in: &metrics)
        Self.assign(summary.achievedHoldTime, to: "achievedHoldTime", in: &metrics)
        Self.assign(summary.maxAltitudeErrorAfterWarmup, to: "maxAltitudeErrorAfterWarmup", in: &metrics)
        Self.assign(summary.maxVerticalVelocityAfterWarmup, to: "maxVerticalVelocityAfterWarmup", in: &metrics)

        try self.init(
            profileID: "referenceQuadrotor",
            task: summary.task,
            scenarioSuiteID: scenarioSuiteID,
            scenarioID: summary.scenarioID,
            seed: summary.seed,
            passed: summary.passed,
            failureReasons: summary.failureReasons,
            evaluatorID: summary.evaluatorID,
            metrics: metrics
        )
    }

    private static func assign(_ value: Double?, to key: String, in metrics: inout [String: Double]) {
        guard let value else { return }
        metrics[key] = value
    }
}
