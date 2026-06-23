import Foundation

public enum LearningProjectComputePreset: String, Codable, Sendable, Equatable, CaseIterable {
    case smoke
    case local
    case standard
    case full
}

public enum LearningProjectComputeAccelerator: String, Codable, Sendable, Equatable, CaseIterable {
    case cpu
    case metal
}

public struct LearningProjectComputeProfile: Codable, Sendable, Equatable {
    public let preset: LearningProjectComputePreset
    public let workerCount: Int
    public let candidateEvaluationConcurrency: Int
    public let requiresMetal: Bool
    public let targetAccelerator: LearningProjectComputeAccelerator
    public let usesMachineOptimizedParallelism: Bool
    public let minimumPopulationSize: Int
    public let estimatedDiskBytes: Int64?

    private enum CodingKeys: String, CodingKey {
        case preset
        case workerCount
        case candidateEvaluationConcurrency
        case requiresMetal
        case targetAccelerator
        case usesMachineOptimizedParallelism
        case minimumPopulationSize
        case estimatedDiskBytes
    }

    public init(
        preset: LearningProjectComputePreset,
        workerCount: Int,
        candidateEvaluationConcurrency: Int,
        requiresMetal: Bool,
        targetAccelerator: LearningProjectComputeAccelerator = .metal,
        usesMachineOptimizedParallelism: Bool = true,
        minimumPopulationSize: Int = 1,
        estimatedDiskBytes: Int64?
    ) {
        self.preset = preset
        self.workerCount = workerCount
        self.candidateEvaluationConcurrency = candidateEvaluationConcurrency
        self.requiresMetal = requiresMetal
        self.targetAccelerator = targetAccelerator
        self.usesMachineOptimizedParallelism = usesMachineOptimizedParallelism
        self.minimumPopulationSize = max(1, minimumPopulationSize)
        self.estimatedDiskBytes = estimatedDiskBytes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let preset = try container.decode(LearningProjectComputePreset.self, forKey: .preset)
        let workerCount = try container.decode(Int.self, forKey: .workerCount)
        let candidateEvaluationConcurrency = try container.decode(
            Int.self,
            forKey: .candidateEvaluationConcurrency
        )
        let requiresMetal = try container.decode(Bool.self, forKey: .requiresMetal)
        let targetAccelerator = try container.decodeIfPresent(
            LearningProjectComputeAccelerator.self,
            forKey: .targetAccelerator
        ) ?? (requiresMetal ? .metal : .cpu)
        let usesMachineOptimizedParallelism = try container.decodeIfPresent(
            Bool.self,
            forKey: .usesMachineOptimizedParallelism
        ) ?? requiresMetal
        let minimumPopulationSize = try container.decodeIfPresent(
            Int.self,
            forKey: .minimumPopulationSize
        ) ?? candidateEvaluationConcurrency
        let estimatedDiskBytes = try container.decodeIfPresent(Int64.self, forKey: .estimatedDiskBytes)

        self.init(
            preset: preset,
            workerCount: workerCount,
            candidateEvaluationConcurrency: candidateEvaluationConcurrency,
            requiresMetal: requiresMetal,
            targetAccelerator: targetAccelerator,
            usesMachineOptimizedParallelism: usesMachineOptimizedParallelism,
            minimumPopulationSize: minimumPopulationSize,
            estimatedDiskBytes: estimatedDiskBytes
        )
    }
}
