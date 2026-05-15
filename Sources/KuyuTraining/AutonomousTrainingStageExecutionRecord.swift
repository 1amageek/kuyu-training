public struct AutonomousTrainingStageExecutionRecord: Codable, Sendable, Equatable {
    public let stageID: String
    public let kind: AutonomousTrainingStageKind
    public let status: AutonomousTrainingStageExecutionStatus
    public let satisfiedGates: [AutonomousSafetyGateKind]
    public let evidence: [AutonomousTrainingStageEvidence]
    public let failureReasons: [String]

    public init(
        stageID: String,
        kind: AutonomousTrainingStageKind,
        status: AutonomousTrainingStageExecutionStatus,
        satisfiedGates: [AutonomousSafetyGateKind],
        evidence: [AutonomousTrainingStageEvidence],
        failureReasons: [String] = []
    ) {
        self.stageID = stageID
        self.kind = kind
        self.status = status
        self.satisfiedGates = satisfiedGates
        self.evidence = evidence
        self.failureReasons = failureReasons
    }
}
