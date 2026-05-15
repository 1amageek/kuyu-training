public struct AutonomousTrainingStagePlan: Codable, Sendable, Equatable {
    public let stageID: String
    public let kind: AutonomousTrainingStageKind
    public let taskProfileIDs: [String]
    public let capabilities: [AutonomousCapability]
    public let requiredEntryGates: [AutonomousSafetyGateKind]
    public let requiredExitGates: [AutonomousSafetyGateKind]
    public let producesModelBundle: Bool

    public init(
        stageID: String,
        kind: AutonomousTrainingStageKind,
        taskProfileIDs: [String],
        capabilities: [AutonomousCapability],
        requiredEntryGates: [AutonomousSafetyGateKind] = [],
        requiredExitGates: [AutonomousSafetyGateKind],
        producesModelBundle: Bool
    ) {
        self.stageID = stageID
        self.kind = kind
        self.taskProfileIDs = taskProfileIDs
        self.capabilities = capabilities
        self.requiredEntryGates = requiredEntryGates
        self.requiredExitGates = requiredExitGates
        self.producesModelBundle = producesModelBundle
    }
}
