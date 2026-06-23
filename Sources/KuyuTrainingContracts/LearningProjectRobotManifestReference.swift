import Foundation

public enum LearningProjectRobotManifestSource: String, Codable, Sendable, Equatable, CaseIterable {
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

public struct LearningProjectRobotManifestReference: Codable, Sendable, Equatable {
    public let robotManifestID: String
    public let source: LearningProjectRobotManifestSource
    public let path: String?
    public let contentHash: String?
    public let robotClass: LearningProjectRobotClass

    public init(
        robotManifestID: String,
        source: LearningProjectRobotManifestSource,
        path: String?,
        contentHash: String?,
        robotClass: LearningProjectRobotClass
    ) {
        self.robotManifestID = robotManifestID
        self.source = source
        self.path = path
        self.contentHash = contentHash
        self.robotClass = robotClass
    }
}
