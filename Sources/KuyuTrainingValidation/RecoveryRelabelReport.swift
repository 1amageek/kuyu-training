public struct RecoveryRelabelReport: Sendable, Codable, Equatable {
    public let sourceEntryCount: Int
    public let relabeledEntryCount: Int
    public let relabeledStepCount: Int
    public let relabeledCutStepCount: Int
    public let skippedEntryCount: Int

    public init(
        sourceEntryCount: Int,
        relabeledEntryCount: Int,
        relabeledStepCount: Int,
        relabeledCutStepCount: Int,
        skippedEntryCount: Int
    ) {
        self.sourceEntryCount = sourceEntryCount
        self.relabeledEntryCount = relabeledEntryCount
        self.relabeledStepCount = relabeledStepCount
        self.relabeledCutStepCount = relabeledCutStepCount
        self.skippedEntryCount = skippedEntryCount
    }
}

public typealias AttitudeRecoveryRelabelReport = RecoveryRelabelReport
