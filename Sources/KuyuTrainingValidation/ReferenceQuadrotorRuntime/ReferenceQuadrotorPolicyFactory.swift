import KuyuScenarios

public protocol ReferenceQuadrotorPolicyFactory: Sendable {
    var policyID: String { get }

    func makePolicy(
        definition: ReferenceQuadrotorScenarioDefinition,
        workerIndex: Int
    ) throws -> any ReferenceQuadrotorEnvironmentPolicy
}

public protocol ReferenceQuadrotorWorkerScopedPolicyFactory: ReferenceQuadrotorPolicyFactory {
    func makeWorkerPolicyFactory(workerIndex: Int) throws -> any ReferenceQuadrotorPolicyFactory
}

public extension ReferenceQuadrotorPolicyFactory {
    func workerScopedFactory(workerIndex: Int) throws -> any ReferenceQuadrotorPolicyFactory {
        if let scopedFactory = self as? any ReferenceQuadrotorWorkerScopedPolicyFactory {
            return try scopedFactory.makeWorkerPolicyFactory(workerIndex: workerIndex)
        }
        return self
    }
}
