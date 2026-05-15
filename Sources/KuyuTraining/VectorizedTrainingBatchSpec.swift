public enum VectorizedWorldExecutionMode: String, Sendable, Codable, Equatable, CaseIterable {
    case isolatedWorlds
    case sharedWorld
}

public enum VectorizedWorldExecutionRequirement: String, Sendable, Codable, Equatable, CaseIterable {
    case acceleratorSharedWorld
    case allowIsolatedWorldFallback
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
        if actionEncoding == .ctbr, actionDimension != 4 {
            throw VectorizedTrainingBatchSpecError.ctbrRequiresFourActions
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
    case ctbrRequiresFourActions
}
