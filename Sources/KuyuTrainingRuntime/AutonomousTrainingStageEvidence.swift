import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation
public struct AutonomousTrainingStageEvidence: Codable, Sendable, Equatable {
    public let kind: AutonomousTrainingStageEvidenceKind
    public let path: String
    public let safetyGate: AutonomousSafetyGateKind?

    public init(
        kind: AutonomousTrainingStageEvidenceKind,
        path: String,
        safetyGate: AutonomousSafetyGateKind? = nil
    ) {
        self.kind = kind
        self.path = path
        self.safetyGate = safetyGate
    }
}
