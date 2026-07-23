import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public struct LearningProjectTemplateCatalog: Sendable {
    public let templates: [LearningProjectTemplate]

    public init(templates: [LearningProjectTemplate] = LearningProjectTemplateCatalog.defaultTemplates) {
        self.templates = templates
    }

    public func template(id: String) -> LearningProjectTemplate? {
        templates.first { $0.templateID == id }
    }

    public static let defaultTemplates: [LearningProjectTemplate] = [
        .droneAutonomyStarter,
        .droneHoverStabilization,
        .droneWaypointNavigation,
        .singlePropLiftRecovery,
        .groundRobotPointNavigation,
        .leggedRobotLocomotion,
        .roArmM1ArmGripperTargetTracking,
        .manipulatorPickAndPlace,
        .automotiveLaneKeeping
    ]
}
