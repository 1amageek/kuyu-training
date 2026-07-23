public struct KuyuOffPolicyTransition: Sendable, Codable, Equatable {
    public let transition: KuyuControlTransition

    public init(transition: KuyuControlTransition) {
        self.transition = transition
    }
}
