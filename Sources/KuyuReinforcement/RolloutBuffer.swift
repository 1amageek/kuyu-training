import KuyuTrainingContracts
public struct RolloutBuffer<Observation: Sendable, Action: Sendable>: Sendable {
    public let observations: [Observation]
    public let actions: [Action]
    public let rewards: [Double]
    public let dones: [Bool]

    public init(
        observations: [Observation],
        actions: [Action],
        rewards: [Double],
        dones: [Bool]
    ) {
        self.observations = observations
        self.actions = actions
        self.rewards = rewards
        self.dones = dones
    }
}
