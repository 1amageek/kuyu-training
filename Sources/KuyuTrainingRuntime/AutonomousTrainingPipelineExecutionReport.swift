import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation
public struct AutonomousTrainingPipelineExecutionReport: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let planID: String
    public let domain: AutonomousOperationDomain
    public let stageRecords: [AutonomousTrainingStageExecutionRecord]
    public let satisfiedTerminalGates: [AutonomousSafetyGateKind]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        planID: String,
        domain: AutonomousOperationDomain,
        stageRecords: [AutonomousTrainingStageExecutionRecord],
        satisfiedTerminalGates: [AutonomousSafetyGateKind]
    ) {
        self.schemaVersion = schemaVersion
        self.planID = planID
        self.domain = domain
        self.stageRecords = stageRecords
        self.satisfiedTerminalGates = satisfiedTerminalGates
    }
}
