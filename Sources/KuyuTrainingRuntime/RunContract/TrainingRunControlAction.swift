import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation
/// Control actions a client may request through `control/command.json`.
///
/// The on-disk command field is a raw string so that trainers can explicitly
/// reject unknown actions instead of failing to decode them.
public enum TrainingRunControlAction: String, Sendable, Codable, Equatable, CaseIterable {
    case pause
    case resume
    case stop
    case checkpoint
}
