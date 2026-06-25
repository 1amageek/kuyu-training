public struct TrainingRunControlSubmission: Sendable, Equatable {
    public let command: TrainingRunControlCommand
    public let liveness: TrainingRunLiveness

    public init(command: TrainingRunControlCommand, liveness: TrainingRunLiveness) {
        self.command = command
        self.liveness = liveness
    }
}
