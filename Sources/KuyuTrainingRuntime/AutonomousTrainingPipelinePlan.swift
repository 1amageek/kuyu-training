import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation
public struct AutonomousTrainingPipelinePlan: Codable, Sendable, Equatable {
    public let planID: String
    public let domain: AutonomousOperationDomain
    public let targetCapabilities: [AutonomousCapability]
    public let stages: [AutonomousTrainingStagePlan]
    public let terminalGates: [AutonomousSafetyGateKind]

    public init(
        planID: String,
        domain: AutonomousOperationDomain,
        targetCapabilities: [AutonomousCapability],
        stages: [AutonomousTrainingStagePlan],
        terminalGates: [AutonomousSafetyGateKind]
    ) {
        self.planID = planID
        self.domain = domain
        self.targetCapabilities = targetCapabilities
        self.stages = stages
        self.terminalGates = terminalGates
    }
}
