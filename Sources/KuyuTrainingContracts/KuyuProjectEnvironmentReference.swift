import Foundation

public struct KuyuProjectEnvironmentReference: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let environmentID: String
    public let displayName: String
    public let domain: AutonomousOperationDomain
    public let task: String
    public let suiteIDs: [Int]

    public init(
        schemaVersion: Int = KuyuProjectEnvironmentReference.currentSchemaVersion,
        environmentID: String,
        displayName: String,
        domain: AutonomousOperationDomain,
        task: String,
        suiteIDs: [Int]
    ) {
        self.schemaVersion = schemaVersion
        self.environmentID = environmentID
        self.displayName = displayName
        self.domain = domain
        self.task = task
        self.suiteIDs = suiteIDs
    }
}
