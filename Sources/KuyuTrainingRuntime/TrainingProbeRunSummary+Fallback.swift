import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

extension TrainingProbeRunSummary {
    static func empty(stage: TrainingProbeStage) -> TrainingProbeRunSummary {
        TrainingProbeRunSummary(
            stage: stage,
            score: -Double.greatestFiniteMagnitude,
            suitePassed: false,
            scenarioCount: 0,
            safetyViolationSeconds: Double.greatestFiniteMagnitude,
            worstOvershootDegrees: nil,
            averageRecoveryTime: nil,
            averageHfStabilityScore: nil,
            diagnostics: TrainingProbeRunDiagnostics.empty
        )
    }

    init(
        stage: TrainingProbeStage,
        score: Double,
        suitePassed: Bool,
        scenarioCount: Int,
        safetyViolationSeconds: Double,
        worstOvershootDegrees: Double?,
        averageRecoveryTime: Double?,
        averageHfStabilityScore: Double?,
        diagnostics: TrainingProbeRunDiagnostics
    ) {
        self.stage = stage
        self.score = score
        self.suitePassed = suitePassed
        self.scenarioCount = scenarioCount
        self.safetyViolationSeconds = safetyViolationSeconds
        self.worstOvershootDegrees = worstOvershootDegrees
        self.averageRecoveryTime = averageRecoveryTime
        self.averageHfStabilityScore = averageHfStabilityScore
        self.diagnostics = diagnostics
    }
}
