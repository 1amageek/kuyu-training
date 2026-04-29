import Foundation

public struct PolicySnapshot: Sendable, Codable, Equatable {
    public let policyId: String
    public let snapshotId: String
    public let modelDescriptorId: String?
    public let modelPath: String?
    public let configHash: String

    public init(
        policyId: String,
        snapshotId: String,
        modelDescriptorId: String? = nil,
        modelPath: String? = nil,
        configHash: String
    ) {
        self.policyId = policyId
        self.snapshotId = snapshotId
        self.modelDescriptorId = modelDescriptorId
        self.modelPath = modelPath
        self.configHash = configHash
    }
}

public protocol PolicyWorkerFactory: Sendable {
    associatedtype Worker: Sendable

    var snapshot: PolicySnapshot { get }

    func makeWorker(workerIndex: Int) throws -> Worker
}
