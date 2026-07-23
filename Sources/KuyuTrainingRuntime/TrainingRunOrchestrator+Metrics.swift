import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

extension TrainingRunOrchestrator {
    func suiteMetrics(
        runID: String,
        iteration: Int,
        output: TrainingScenarioRunOutput,
        score: Double
    ) -> [TrainingMetricRecord] {
        let evaluations = output.summary.evaluations
        let total = max(evaluations.count, 1)
        let passed = evaluations.filter(\.passed).count
        let failures = evaluations.filter { !$0.passed || $0.failureReason != nil }.count
        let safetyViolation = evaluations.reduce(0.0) { partial, evaluation in
            partial + evaluation.sustainedViolationSeconds
        }
        return [
            TrainingMetricRecord(runID: runID, iteration: iteration, kind: .score, value: score),
            TrainingMetricRecord(runID: runID, iteration: iteration, kind: .passRate, value: Double(passed) / Double(total)),
            TrainingMetricRecord(runID: runID, iteration: iteration, kind: .failureRate, value: Double(failures) / Double(total)),
            TrainingMetricRecord(runID: runID, iteration: iteration, kind: .safetyViolation, value: safetyViolation),
            TrainingMetricRecord(
                runID: runID,
                iteration: iteration,
                kind: .evaluationScenarioCount,
                value: Double(evaluations.count)
            ),
        ]
    }

    public nonisolated static func score(from summary: TrainingScenarioRunSummary) -> Double {
        var score = summary.suitePassed ? 1.0 : 0.0
        if let worstOvershoot = summary.aggregate.worstOvershootDegrees {
            score -= min(1.0, worstOvershoot / 90.0) * 0.4
        }
        if let recovery = summary.aggregate.averageRecoveryTime {
            score -= min(1.0, recovery / 5.0) * 0.3
        }
        if let hf = summary.aggregate.averageHfStabilityScore {
            score += max(0.0, min(hf, 1.0)) * 0.2
        }
        return score
    }

    func requestHash(_ request: SimulationRunRequest, robotIdentity: RobotManifestIdentity?) -> String {
        [
            request.controller.rawValue,
            request.taskMode.rawValue,
            "\(request.cutPeriodSteps)",
            request.determinism.tier.rawValue,
            robotIdentity?.sha256 ?? request.robotManifestPath,
        ].joined(separator: "|")
    }
}
