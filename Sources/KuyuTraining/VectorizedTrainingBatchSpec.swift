public enum VectorizedWorldExecutionMode: String, Sendable, Codable, Equatable, CaseIterable {
    case isolatedWorlds
    case sharedWorld
}

public enum VectorizedWorldExecutionRequirement: String, Sendable, Codable, Equatable, CaseIterable {
    /// Require the accelerator shared-world (GPU tensor) path. Evaluation fails
    /// fast if any scenario is not tensor-world capable. Use for GPU-capable
    /// tasks where accelerated batched physics is a hard performance contract.
    case acceleratorSharedWorld
    /// Prefer the accelerator shared-world path, but fall back to isolated CPU
    /// worlds (full physics, swap/HF stress) when any scenario is not
    /// tensor-world capable. Use for full-physics tasks such as attitude and the
    /// A1 swap/HF-stress suites that the tensor world cannot model.
    case preferAcceleratorSharedWorld
}

public struct VectorizedTrainingBatchSpec: Sendable, Codable, Equatable {
    public let populationSize: Int
    public let worldCount: Int
    public let rolloutHorizon: Int
    public let historyLength: Int
    public let observationDimension: Int
    public let actionDimension: Int
    public let actionEncoding: LearningProjectPolicyActionEncoding
    public let executionMode: VectorizedWorldExecutionMode
    public let requiresAccelerator: LearningProjectComputeAccelerator

    public init(
        populationSize: Int,
        worldCount: Int,
        rolloutHorizon: Int,
        historyLength: Int,
        observationDimension: Int,
        actionDimension: Int,
        actionEncoding: LearningProjectPolicyActionEncoding,
        executionMode: VectorizedWorldExecutionMode,
        requiresAccelerator: LearningProjectComputeAccelerator
    ) throws {
        guard populationSize > 0 else {
            throw VectorizedTrainingBatchSpecError.nonPositivePopulationSize
        }
        guard worldCount > 0 else {
            throw VectorizedTrainingBatchSpecError.nonPositiveWorldCount
        }
        guard rolloutHorizon > 0 else {
            throw VectorizedTrainingBatchSpecError.nonPositiveRolloutHorizon
        }
        guard historyLength > 0 else {
            throw VectorizedTrainingBatchSpecError.nonPositiveHistoryLength
        }
        guard observationDimension > 0 else {
            throw VectorizedTrainingBatchSpecError.nonPositiveObservationDimension
        }
        guard actionDimension > 0 else {
            throw VectorizedTrainingBatchSpecError.nonPositiveActionDimension
        }
        self.populationSize = populationSize
        self.worldCount = worldCount
        self.rolloutHorizon = rolloutHorizon
        self.historyLength = historyLength
        self.observationDimension = observationDimension
        self.actionDimension = actionDimension
        self.actionEncoding = actionEncoding
        self.executionMode = executionMode
        self.requiresAccelerator = requiresAccelerator
    }

    public var actorObservationShape: [Int] {
        [populationSize, worldCount, historyLength, observationDimension]
    }

    public var actionShape: [Int] {
        [populationSize, worldCount, actionDimension]
    }
}

public enum VectorizedTrainingBatchSpecError: Error, Sendable, Equatable {
    case nonPositivePopulationSize
    case nonPositiveWorldCount
    case nonPositiveRolloutHorizon
    case nonPositiveHistoryLength
    case nonPositiveObservationDimension
    case nonPositiveActionDimension
}
