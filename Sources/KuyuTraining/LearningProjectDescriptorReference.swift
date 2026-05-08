import Foundation

public enum LearningProjectDescriptorSource: String, Codable, Sendable, Equatable, CaseIterable {
    case bundled
    case filePath
    case remote
    case generated
}

public enum LearningProjectRobotClass: String, Codable, Sendable, Equatable, CaseIterable {
    case aerialVehicle
    case groundVehicle
    case leggedRobot
    case manipulator
    case mobileRobot
    case genericRobot
}

public struct LearningProjectDescriptorReference: Codable, Sendable, Equatable {
    public let descriptorID: String
    public let source: LearningProjectDescriptorSource
    public let path: String?
    public let contentHash: String?
    public let robotClass: LearningProjectRobotClass

    public init(
        descriptorID: String,
        source: LearningProjectDescriptorSource,
        path: String?,
        contentHash: String?,
        robotClass: LearningProjectRobotClass
    ) {
        self.descriptorID = descriptorID
        self.source = source
        self.path = path
        self.contentHash = contentHash
        self.robotClass = robotClass
    }
}
