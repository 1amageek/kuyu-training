import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation
public struct AutonomousTrainingStageCompletion: Sendable, Equatable {
    public let stageID: String
    public let satisfiedGates: [AutonomousSafetyGateKind]
    public let evidence: [AutonomousTrainingStageEvidence]

    public init(
        stageID: String,
        satisfiedGates: [AutonomousSafetyGateKind],
        evidence: [AutonomousTrainingStageEvidence]
    ) {
        self.stageID = stageID
        self.satisfiedGates = satisfiedGates
        self.evidence = evidence
    }
}
