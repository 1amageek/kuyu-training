import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public struct TrainingProbeRunSummary: Sendable, Codable, Equatable {
    public let stage: TrainingProbeStage
    public let score: Double
    public let suitePassed: Bool
    public let scenarioCount: Int
    public let safetyViolationSeconds: Double
    public let worstOvershootDegrees: Double?
    public let averageRecoveryTime: Double?
    public let averageHfStabilityScore: Double?
    public let diagnostics: TrainingProbeRunDiagnostics

    public init(stage: TrainingProbeStage, output: TrainingScenarioRunOutput) {
        self.stage = stage
        self.score = TrainingRunOrchestrator.score(from: output.summary)
        self.suitePassed = output.summary.suitePassed
        self.scenarioCount = output.summary.evaluations.count
        self.safetyViolationSeconds = output.summary.evaluations.reduce(0.0) { partial, evaluation in
            partial + evaluation.sustainedViolationSeconds
        }
        self.worstOvershootDegrees = output.summary.aggregate.worstOvershootDegrees
        self.averageRecoveryTime = output.summary.aggregate.averageRecoveryTime
        self.averageHfStabilityScore = output.summary.aggregate.averageHfStabilityScore
        self.diagnostics = TrainingProbeRunDiagnostics(output: output)
    }
}
