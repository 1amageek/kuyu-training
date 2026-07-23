import KuyuCore

public struct RolloutSummary: Sendable, Codable, Equatable {
    public let episodeCount: Int
    public let rewardDescriptor: RewardDescriptor?
    public let rewardSum: Double
    public let doneCount: Int
    public let truncatedCount: Int
    public let failureCount: Int
    public let cancelledCount: Int

    public init(episodes: [RolloutEpisode]) {
        self.episodeCount = episodes.count
        self.rewardDescriptor = episodes.first?.rewardDescriptor
        self.rewardSum = episodes.reduce(0.0) { $0 + $1.rewardSum }
        self.doneCount = episodes.filter(\.done).count
        self.truncatedCount = episodes.filter(\.truncated).count
        self.failureCount = episodes.filter { $0.failureReason != nil }.count
        self.cancelledCount = episodes.filter(\.cancelled).count
    }
}
