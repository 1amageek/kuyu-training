import Foundation

public enum LearningProjectComputePreset: String, Codable, Sendable, Equatable, CaseIterable {
    case smoke
    case local
    case standard
    case full
}

public struct LearningProjectComputeProfile: Codable, Sendable, Equatable {
    public let preset: LearningProjectComputePreset
    public let workerCount: Int
    public let candidateEvaluationConcurrency: Int
    public let requiresMetal: Bool
    public let estimatedDiskBytes: Int64?

    public init(
        preset: LearningProjectComputePreset,
        workerCount: Int,
        candidateEvaluationConcurrency: Int,
        requiresMetal: Bool,
        estimatedDiskBytes: Int64?
    ) {
        self.preset = preset
        self.workerCount = workerCount
        self.candidateEvaluationConcurrency = candidateEvaluationConcurrency
        self.requiresMetal = requiresMetal
        self.estimatedDiskBytes = estimatedDiskBytes
    }
}
