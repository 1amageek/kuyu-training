public protocol TrainingProgressReporting: Sendable {
    func report(_ progress: TrainingWorkProgress) async throws
}
