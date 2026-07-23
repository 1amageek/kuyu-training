import Foundation
import KuyuTrainingContracts

public struct KuyuDatasetValidationSession: Sendable {
    private let manifest: KuyuDatasetManifest
    private let validator: KuyuDatasetValidator
    private var count: UInt64 = 0
    private var previousRecord: KuyuDatasetRecord?

    init(manifest: KuyuDatasetManifest, validator: KuyuDatasetValidator) {
        self.manifest = manifest
        self.validator = validator
    }

    public mutating func consume(_ record: KuyuDatasetRecord) throws {
        try validateIdentity(record)
        try validateBoundaryBeforeAppending(record)
        try validatePayload(record)
        try validateContinuity(record)
        previousRecord = record
        count += 1
    }

    public mutating func finish() throws {
        guard count > 0 else {
            throw KuyuDatasetValidator.ValidationError.emptyDataset
        }
        guard count == manifest.recordCount else {
            throw KuyuDatasetValidator.ValidationError.recordCountMismatch(
                expected: manifest.recordCount,
                actual: count
            )
        }
        if previousRecord?.boundary?.kind == .continues {
            throw KuyuDatasetValidator.ValidationError.finalBoundaryContinues
        }
        if case .recurrent(let recurrent) = manifest.descriptor.policyContext,
           manifest.descriptor.recordKind == .onPolicyTransition,
           recurrent.lossStartTransitionIndex >= Int(count) {
            throw KuyuDatasetValidator.ValidationError.invalidPolicyContext(
                "loss start is outside the trajectory"
            )
        }
    }

    private func validateIdentity(_ record: KuyuDatasetRecord) throws {
        guard record.kind == manifest.descriptor.recordKind else {
            throw KuyuDatasetValidator.ValidationError.recordKindMismatch(
                index: count,
                expected: manifest.descriptor.recordKind,
                actual: record.kind
            )
        }
        let coordinate = record.coordinate
        let identity = manifest.descriptor.identity
        guard coordinate.episodeID == identity.episodeID else {
            throw coordinateError(field: "episodeID", expected: identity.episodeID, actual: coordinate.episodeID)
        }
        guard coordinate.segmentID == identity.segmentID else {
            throw coordinateError(field: "segmentID", expected: identity.segmentID, actual: coordinate.segmentID)
        }
        guard coordinate.segmentIndex == identity.segmentIndex else {
            throw coordinateError(
                field: "segmentIndex",
                expected: String(identity.segmentIndex),
                actual: String(coordinate.segmentIndex)
            )
        }
        guard coordinate.transitionIndex == Int(count) else {
            throw KuyuDatasetValidator.ValidationError.transitionIndexMismatch(
                expected: Int(count),
                actual: coordinate.transitionIndex
            )
        }
        guard !coordinate.decisionID.isEmpty else {
            throw KuyuDatasetValidator.ValidationError.invalidRecord(index: count, reason: "empty decisionID")
        }
    }

    private func validateBoundaryBeforeAppending(_ record: KuyuDatasetRecord) throws {
        guard let previousBoundary = previousRecord?.boundary else { return }
        guard previousBoundary.kind == .continues else {
            throw KuyuDatasetValidator.ValidationError.recordAfterClosedBoundary(
                index: count,
                previous: previousBoundary.kind
            )
        }
        guard record.boundary != nil else {
            throw KuyuDatasetValidator.ValidationError.invalidRecord(
                index: count,
                reason: "mixed bounded and unbounded records"
            )
        }
    }

    private func validatePayload(_ record: KuyuDatasetRecord) throws {
        switch record {
        case .demonstration(let sample):
            try validateDemonstration(sample)
        case .onPolicyTransition(let sample):
            try validateControlTransition(sample.transition)
            try validateBehavior(sample.behavior, transition: sample.transition)
        case .offPolicyTransition(let sample):
            try validateControlTransition(sample.transition)
        case .worldTransition(let sample):
            try validateWorldTransition(sample)
        }
    }

    private func validateDemonstration(_ sample: KuyuDemonstrationSample) throws {
        let spaces = manifest.descriptor.spaces
        try validateVector(
            sample.observation.values,
            expected: spaces.observation.channels.count,
            field: "observation"
        )
        try validateStateFacts(sample.stateFacts, field: "stateFacts")
        try validateVector(
            sample.teacherAction.values,
            expected: spaces.policyAction.channels.count,
            field: "teacherAction"
        )
        try validateBounds(
            sample.teacherAction.values,
            channels: spaces.policyAction.channels,
            field: "teacherAction"
        )
        try validateFinite(sample.observation.time, field: "observation.time")
        guard !sample.teacherID.isEmpty else {
            throw KuyuDatasetValidator.ValidationError.invalidRecord(index: count, reason: "empty teacherID")
        }
    }

    private func validateControlTransition(_ transition: KuyuControlTransition) throws {
        let spaces = manifest.descriptor.spaces
        try validateVector(
            transition.sourceObservation.values,
            expected: spaces.observation.channels.count,
            field: "sourceObservation"
        )
        try validateVector(
            transition.outcomeObservation.values,
            expected: spaces.observation.channels.count,
            field: "outcomeObservation"
        )
        try validateStateFacts(transition.sourceStateFacts, field: "sourceStateFacts")
        try validateStateFacts(transition.outcomeStateFacts, field: "outcomeStateFacts")
        try validateVector(
            transition.policyAction.values,
            expected: spaces.policyAction.channels.count,
            field: "policyAction"
        )
        try validateBounds(
            transition.policyAction.values,
            channels: spaces.policyAction.channels,
            field: "policyAction"
        )
        try validateVector(
            transition.actuatorCommand.values,
            expected: spaces.actuatorCommand.channels.count,
            field: "actuatorCommand"
        )
        try validateBounds(
            transition.actuatorCommand.values,
            channels: spaces.actuatorCommand.channels,
            field: "actuatorCommand"
        )
        try validateRealizedControl(transition.realizedControl)
        try validateFinite(transition.reward, field: "reward")
        try validateFinite(transition.safetyCost, field: "safetyCost")
        try validateInterval(
            transition.interval,
            sourceTime: transition.sourceObservation.time,
            outcomeTime: transition.outcomeObservation.time,
            boundary: transition.boundary
        )
        try validateBoundary(transition.boundary)
    }

    private func validateBehavior(
        _ behavior: KuyuBehaviorPolicyEvidence,
        transition: KuyuControlTransition
    ) throws {
        guard let policy = manifest.descriptor.policy else {
            throw behaviorError("manifest policy missing")
        }
        guard behavior.policyID == policy.policyID,
              behavior.checkpointDigest == policy.checkpointDigest,
              behavior.distributionContractDigest == policy.distributionContractDigest else {
            throw behaviorError("policy identity mismatch")
        }
        let actionCount = manifest.descriptor.spaces.policyAction.channels.count
        guard behavior.distributionVersion > 0,
              behavior.distributionKinds.count == actionCount else {
            throw behaviorError("non-positive distribution version")
        }
        try validateBehaviorVector(behavior.baseMean, expected: actionCount, field: "baseMean")
        try validateBehaviorVector(
            behavior.transformedMean,
            expected: actionCount,
            field: "transformedMean"
        )
        try validateBehaviorVector(
            behavior.baseLogStandardDeviation,
            expected: actionCount,
            field: "baseLogStandardDeviation"
        )
        try validateBehaviorVector(
            behavior.preTransformSample,
            expected: actionCount,
            field: "preTransformSample"
        )
        try validateBehaviorVector(
            behavior.transformedAction,
            expected: actionCount,
            field: "transformedAction"
        )
        guard behavior.transformedAction == transition.policyAction.values else {
            throw behaviorError("transformed action mismatch")
        }
        guard behavior.logProbability.isFinite else {
            throw behaviorError("non-finite log probability")
        }
        if let rewardValue = behavior.rewardValue, !rewardValue.isFinite {
            throw behaviorError("non-finite reward value")
        }
        if let costValue = behavior.costValue, !costValue.isFinite {
            throw behaviorError("non-finite cost value")
        }

        switch manifest.descriptor.policyContext {
        case .fixedHistory:
            guard behavior.inputRecurrentStateDigest == nil,
                  behavior.outputRecurrentStateDigest == nil else {
                throw behaviorError("fixed-history evidence contains recurrent state")
            }
        case .recurrent(let recurrent):
            guard let inputDigest = behavior.inputRecurrentStateDigest,
                  let outputDigest = behavior.outputRecurrentStateDigest else {
                throw behaviorError("recurrent state digest missing")
            }
            try validator.validateDigest(inputDigest, field: "behavior.inputRecurrentStateDigest")
            try validator.validateDigest(outputDigest, field: "behavior.outputRecurrentStateDigest")
            if count == 0, inputDigest != recurrent.initialStateDigest {
                throw behaviorError("initial recurrent state digest mismatch")
            }
        case nil:
            throw behaviorError("policy context missing")
        }
    }

    private func validateWorldTransition(_ transition: KuyuWorldTransition) throws {
        guard let worldState = manifest.descriptor.spaces.worldState else {
            throw KuyuDatasetValidator.ValidationError.invalidRecord(index: count, reason: "world state space missing")
        }
        try validateVector(transition.sourceState.values, expected: worldState.channels.count, field: "sourceState")
        try validateVector(transition.outcomeState.values, expected: worldState.channels.count, field: "outcomeState")
        try validateVector(
            transition.actuatorCommand.values,
            expected: manifest.descriptor.spaces.actuatorCommand.channels.count,
            field: "actuatorCommand"
        )
        for event in transition.events {
            guard !event.id.isEmpty else {
                throw KuyuDatasetValidator.ValidationError.invalidRecord(index: count, reason: "empty event id")
            }
            guard event.physicsTickOffset < transition.interval.physicsTickCount else {
                throw KuyuDatasetValidator.ValidationError.invalidRecord(
                    index: count,
                    reason: "event tick is outside the interval"
                )
            }
            try validateFiniteVector(event.values, field: "event.\(event.id)")
        }
        try validateInterval(transition.interval, sourceTime: nil, outcomeTime: nil, boundary: transition.boundary)
        try validateBoundary(transition.boundary)
    }

    private func validateStateFacts(_ facts: KuyuControlTransition.StateFacts, field: String) throws {
        let expected = manifest.descriptor.spaces.criticState?.channels.count ?? 0
        try validateVector(facts.values, expected: expected, field: field)
    }

    private func validateRealizedControl(_ control: KuyuControlTransition.RealizedControl) throws {
        let driveCount = manifest.descriptor.spaces.realizedControl.channels.count
        var seen = Set<Int>()
        for intent in control.driveIntents {
            guard intent.driveIndex >= 0,
                  intent.driveIndex < driveCount,
                  seen.insert(intent.driveIndex).inserted else {
                throw KuyuDatasetValidator.ValidationError.invalidRecord(
                    index: count,
                    reason: "invalid or duplicate drive intent"
                )
            }
            try validateFinite(intent.activation, field: "driveIntent.activation")
            try validateFiniteVector(intent.parameters, field: "driveIntent.parameters")
        }
        for correction in control.reflexCorrections {
            guard correction.driveIndex >= 0, correction.driveIndex < driveCount else {
                throw KuyuDatasetValidator.ValidationError.invalidRecord(
                    index: count,
                    reason: "invalid reflex correction index"
                )
            }
            try validateFinite(correction.clamp, field: "reflex.clamp")
            try validateFinite(correction.damping, field: "reflex.damping")
            try validateFinite(correction.delta, field: "reflex.delta")
        }
    }

    private func validateInterval(
        _ interval: KuyuControlInterval,
        sourceTime: Double?,
        outcomeTime: Double?,
        boundary: KuyuTrajectoryBoundary
    ) throws {
        let values = [interval.startTime, interval.endTime, interval.actualDuration]
        guard values.allSatisfy(\.isFinite), interval.actualDuration > 0, interval.physicsTickCount > 0 else {
            throw KuyuDatasetValidator.ValidationError.invalidInterval(index: count, reason: "invalid interval values")
        }
        let tolerance = 1e-9
        guard abs((interval.endTime - interval.startTime) - interval.actualDuration) <= tolerance else {
            throw KuyuDatasetValidator.ValidationError.invalidInterval(index: count, reason: "duration mismatch")
        }
        let completedTickDuration = manifest.descriptor.timing.physicsTimeStep
            * Double(interval.physicsTickCount)
        guard abs(interval.actualDuration - completedTickDuration) <= tolerance else {
            throw KuyuDatasetValidator.ValidationError.invalidInterval(
                index: count,
                reason: "physics tick duration mismatch"
            )
        }
        if let sourceTime, abs(sourceTime - interval.startTime) > tolerance {
            throw KuyuDatasetValidator.ValidationError.invalidInterval(index: count, reason: "source time mismatch")
        }
        if let outcomeTime, abs(outcomeTime - interval.endTime) > tolerance {
            throw KuyuDatasetValidator.ValidationError.invalidInterval(index: count, reason: "outcome time mismatch")
        }
        let nominalDuration = manifest.descriptor.timing.physicsTimeStep
            * Double(manifest.descriptor.timing.controlPeriodTicks)
        guard interval.actualDuration <= nominalDuration + tolerance,
              interval.physicsTickCount <= manifest.descriptor.timing.controlPeriodTicks else {
            throw KuyuDatasetValidator.ValidationError.invalidInterval(index: count, reason: "interval exceeds control period")
        }
        if boundary.kind == .continues {
            guard abs(interval.actualDuration - nominalDuration) <= tolerance,
                  interval.physicsTickCount == manifest.descriptor.timing.controlPeriodTicks else {
                throw KuyuDatasetValidator.ValidationError.invalidInterval(
                    index: count,
                    reason: "continuing interval is incomplete"
                )
            }
        }
    }

    private func validateContinuity(_ record: KuyuDatasetRecord) throws {
        guard let previousRecord else { return }
        switch (previousRecord, record) {
        case (.onPolicyTransition(let previous), .onPolicyTransition(let current)):
            try validateControlContinuity(previous.transition, current.transition)
            if case .recurrent = manifest.descriptor.policyContext,
               previous.behavior.outputRecurrentStateDigest
                != current.behavior.inputRecurrentStateDigest {
                throw KuyuDatasetValidator.ValidationError.transitionDiscontinuity(
                    index: count,
                    field: "recurrentStateDigest"
                )
            }
        case (.offPolicyTransition(let previous), .offPolicyTransition(let current)):
            try validateControlContinuity(previous.transition, current.transition)
        case (.worldTransition(let previous), .worldTransition(let current)):
            guard previous.outcomeState == current.sourceState else {
                throw KuyuDatasetValidator.ValidationError.transitionDiscontinuity(
                    index: count,
                    field: "worldState"
                )
            }
            guard abs(previous.interval.endTime - current.interval.startTime) <= 1e-9 else {
                throw KuyuDatasetValidator.ValidationError.transitionDiscontinuity(
                    index: count,
                    field: "worldTime"
                )
            }
        case (.demonstration, .demonstration):
            break
        default:
            throw KuyuDatasetValidator.ValidationError.invalidRecord(index: count, reason: "mixed record kinds")
        }
    }

    private func validateControlContinuity(
        _ previous: KuyuControlTransition,
        _ current: KuyuControlTransition
    ) throws {
        guard previous.outcomeObservation == current.sourceObservation else {
            throw KuyuDatasetValidator.ValidationError.transitionDiscontinuity(
                index: count,
                field: "observation"
            )
        }
        guard previous.outcomeStateFacts == current.sourceStateFacts else {
            throw KuyuDatasetValidator.ValidationError.transitionDiscontinuity(
                index: count,
                field: "stateFacts"
            )
        }
    }

    private func validateBoundary(_ boundary: KuyuTrajectoryBoundary) throws {
        switch boundary {
        case .continues:
            break
        case .terminal(let terminal):
            guard !terminal.reason.isEmpty else {
                throw KuyuDatasetValidator.ValidationError.invalidRecord(
                    index: count,
                    reason: "empty terminal reason"
                )
            }
        case .truncated(let truncation):
            guard !truncation.reason.isEmpty else {
                throw KuyuDatasetValidator.ValidationError.invalidRecord(
                    index: count,
                    reason: "empty truncation reason"
                )
            }
        case .segmentEnd(let segmentEnd):
            if let token = segmentEnd.continuationToken, token.isEmpty {
                throw KuyuDatasetValidator.ValidationError.invalidRecord(
                    index: count,
                    reason: "empty continuation token"
                )
            }
        }
    }

    private func validateVector(_ values: [Double], expected: Int, field: String) throws {
        guard values.count == expected else {
            throw KuyuDatasetValidator.ValidationError.vectorDimensionMismatch(
                index: count,
                field: field,
                expected: expected,
                actual: values.count
            )
        }
        try validateFiniteVector(values, field: field)
    }

    private func validateBounds(
        _ values: [Double],
        channels: [KuyuDatasetDescriptor.Channel],
        field: String
    ) throws {
        let tolerance = 1e-9
        for (index, value) in values.enumerated() {
            guard let lower = channels[index].lowerBound,
                  let upper = channels[index].upperBound,
                  value >= lower - tolerance,
                  value <= upper + tolerance else {
                if channels[index].lowerBound == nil, channels[index].upperBound == nil {
                    continue
                }
                throw KuyuDatasetValidator.ValidationError.invalidRecord(
                    index: count,
                    reason: "\(field) is outside channel bounds at index \(index)"
                )
            }
        }
    }

    private func validateFiniteVector(_ values: [Double], field: String) throws {
        guard values.allSatisfy(\.isFinite) else {
            throw KuyuDatasetValidator.ValidationError.nonFiniteValue(index: count, field: field)
        }
    }

    private func validateFinite(_ value: Double, field: String) throws {
        guard value.isFinite else {
            throw KuyuDatasetValidator.ValidationError.nonFiniteValue(index: count, field: field)
        }
    }

    private func validateBehaviorVector(_ values: [Double], expected: Int, field: String) throws {
        guard values.count == expected, values.allSatisfy(\.isFinite) else {
            throw behaviorError("invalid \(field)")
        }
    }

    private func behaviorError(_ reason: String) -> KuyuDatasetValidator.ValidationError {
        .invalidBehaviorEvidence(index: count, reason: reason)
    }

    private func coordinateError(
        field: String,
        expected: String,
        actual: String
    ) -> KuyuDatasetValidator.ValidationError {
        .coordinateMismatch(index: count, field: field, expected: expected, actual: actual)
    }
}
