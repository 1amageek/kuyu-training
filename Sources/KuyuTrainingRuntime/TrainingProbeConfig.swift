import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public struct TrainingProbeConfig: Sendable, Equatable {
    public let probeID: String
    public let minScoreDelta: Double
    public let requireAcceptedCheckpoint: Bool
    public let requireTeacherPass: Bool
    public let requireTrainedPass: Bool

    public init(
        probeID: String = UUID().uuidString,
        minScoreDelta: Double = 0,
        requireAcceptedCheckpoint: Bool = true,
        requireTeacherPass: Bool = true,
        requireTrainedPass: Bool = true
    ) {
        self.probeID = probeID
        self.minScoreDelta = minScoreDelta
        self.requireAcceptedCheckpoint = requireAcceptedCheckpoint
        self.requireTeacherPass = requireTeacherPass
        self.requireTrainedPass = requireTrainedPass
    }
}
