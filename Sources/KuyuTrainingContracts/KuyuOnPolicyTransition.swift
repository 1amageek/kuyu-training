public struct KuyuOnPolicyTransition: Sendable, Codable, Equatable {
    public let transition: KuyuControlTransition
    public let behavior: KuyuBehaviorPolicyEvidence

    public init(transition: KuyuControlTransition, behavior: KuyuBehaviorPolicyEvidence) {
        self.transition = transition
        self.behavior = behavior
    }
}
