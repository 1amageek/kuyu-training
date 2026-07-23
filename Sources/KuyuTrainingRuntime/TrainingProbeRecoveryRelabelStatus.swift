import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public struct TrainingProbeRecoveryRelabelStatus: Sendable, Codable, Equatable {
    public let attempted: Bool
    public let datasetDirectory: URL?
    public let report: RecoveryRelabelReport?
    public let failureReason: String?

    public init(
        attempted: Bool,
        datasetDirectory: URL?,
        report: RecoveryRelabelReport?,
        failureReason: String?
    ) {
        self.attempted = attempted
        self.datasetDirectory = datasetDirectory
        self.report = report
        self.failureReason = failureReason
    }

    public static func skipped(reason: String) -> TrainingProbeRecoveryRelabelStatus {
        TrainingProbeRecoveryRelabelStatus(
            attempted: false,
            datasetDirectory: nil,
            report: nil,
            failureReason: reason
        )
    }
}
