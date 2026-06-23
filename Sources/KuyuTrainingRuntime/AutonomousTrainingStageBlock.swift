import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation
public struct AutonomousTrainingStageBlock: Sendable, Equatable {
    public let stageID: String
    public let failureReasons: [String]
    public let evidence: [AutonomousTrainingStageEvidence]

    public init(
        stageID: String,
        failureReasons: [String],
        evidence: [AutonomousTrainingStageEvidence] = []
    ) {
        self.stageID = stageID
        self.failureReasons = failureReasons
        self.evidence = evidence
    }
}
