import Foundation
import KuyuCore

public struct RolloutTransition: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Sendable, Equatable {
        case emptyDecisionID
        case nonIncreasingTime(observationTime: Double, outcomeTime: Double)
        case outcomeObservationLogMismatch
        case driveIntentMismatch
        case reflexCorrectionMismatch
        case actuatorValueMismatch
        case policyActionDimensionMismatch(expected: Int, actual: Int)
        case behaviorMeanDimensionMismatch(expected: Int, actual: Int)
    }

    public let decisionID: String
    public let actionObservation: EnvironmentObservation
    /// The environment action after all policy-space realization has happened.
    public let action: EnvironmentAction
    public let policyAction: RolloutPolicyAction
    public let behaviorStatistics: RolloutBehaviorStatistics?
    public let outcome: EnvironmentStep

    /// Compatibility initializer for direct-motor and DriveIntent policies.
    /// New control-law policies must use the initializer that supplies both
    /// policy and applied actions.
    public init(
        decisionID: String,
        actionObservation: EnvironmentObservation,
        action: EnvironmentAction,
        outcome: EnvironmentStep
    ) throws {
        let values: [Double]
        switch action {
        case .driveIntents(let drives, _):
            values = drives.sorted { $0.index.rawValue < $1.index.rawValue }.map(\.activation)
        case .actuatorValues(let actuatorValues):
            values = actuatorValues.sorted { $0.index.rawValue < $1.index.rawValue }.map(\.value)
        }
        try self.init(
            decisionID: decisionID,
            actionObservation: actionObservation,
            policyAction: try RolloutPolicyAction(encoding: "environment", values: values),
            appliedAction: action,
            behaviorStatistics: nil,
            outcome: outcome
        )
    }

    public init(
        decisionID: String,
        actionObservation: EnvironmentObservation,
        policyAction: RolloutPolicyAction,
        appliedAction: EnvironmentAction,
        behaviorStatistics: RolloutBehaviorStatistics? = nil,
        outcome: EnvironmentStep
    ) throws {
        guard !decisionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyDecisionID
        }
        guard outcome.observation.time.time > actionObservation.time.time else {
            throw ValidationError.nonIncreasingTime(
                observationTime: actionObservation.time.time,
                outcomeTime: outcome.observation.time.time
            )
        }
        guard outcome.observation == EnvironmentObservation(log: outcome.log) else {
            throw ValidationError.outcomeObservationLogMismatch
        }
        switch appliedAction {
        case .driveIntents(let drives, let corrections):
            guard drives == outcome.log.driveIntents else {
                throw ValidationError.driveIntentMismatch
            }
            guard corrections == outcome.log.reflexCorrections else {
                throw ValidationError.reflexCorrectionMismatch
            }
        case .actuatorValues(let values):
            guard values == outcome.log.actuatorValues else {
                throw ValidationError.actuatorValueMismatch
            }
        }
        guard policyAction.values.count > 0 else {
            throw ValidationError.policyActionDimensionMismatch(expected: 1, actual: 0)
        }
        if let behaviorStatistics {
            guard behaviorStatistics.mean.count == policyAction.values.count else {
                throw ValidationError.behaviorMeanDimensionMismatch(
                    expected: policyAction.values.count,
                    actual: behaviorStatistics.mean.count
                )
            }
        }
        self.decisionID = decisionID
        self.actionObservation = actionObservation
        self.action = appliedAction
        self.policyAction = policyAction
        self.behaviorStatistics = behaviorStatistics
        self.outcome = outcome
    }

    public var duration: TimeInterval {
        outcome.observation.time.time - actionObservation.time.time
    }
}
