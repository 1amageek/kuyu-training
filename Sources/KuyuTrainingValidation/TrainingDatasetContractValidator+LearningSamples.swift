import Foundation

extension TrainingDatasetContractValidator {
    func validateCausalTransitions(
        _ dataset: TrainingDataset,
        tolerance: Double,
        requiresBehaviorStatistics: Bool
    ) throws {
        guard dataset.metadata.purpose == .reinforcementRollout
                || dataset.metadata.purpose == .worldModel else {
            throw ValidationError.invalidCausalPurpose(dataset.metadata.purpose)
        }
        guard let physicsTimeStep = dataset.metadata.physicsTimeStep else {
            throw ValidationError.missingPhysicsTimeStep
        }
        guard let controlPeriodSteps = dataset.metadata.controlPeriodSteps,
              controlPeriodSteps > 0 else {
            throw ValidationError.missingControlPeriodSteps
        }
        let expectedControlTimeStep = physicsTimeStep * Double(controlPeriodSteps)
        guard abs(expectedControlTimeStep - dataset.metadata.timeStep) <= tolerance else {
            throw ValidationError.controlTimeStepMismatch(
                expected: expectedControlTimeStep,
                actual: dataset.metadata.timeStep
            )
        }

        var decisionIDs: Set<String> = []
        var previous: TrainingDatasetRecord?
        for (recordIndex, record) in dataset.records.enumerated() {
            guard let decisionID = record.policyDecisionID,
                  !decisionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.missingPolicyDecisionID(recordIndex: recordIndex)
            }
            guard decisionIDs.insert(decisionID).inserted else {
                throw ValidationError.duplicatePolicyDecisionID(decisionID)
            }
            guard let actionObservationTime = record.actionObservationTime else {
                throw ValidationError.missingActionObservationTime(recordIndex: recordIndex)
            }
            let duration = record.time - actionObservationTime
            guard duration > 0 else {
                throw ValidationError.nonPositiveTransitionDuration(
                    recordIndex: recordIndex,
                    duration: duration
                )
            }
            guard duration <= dataset.metadata.timeStep + tolerance else {
                throw ValidationError.transitionDurationExceedsControlPeriod(
                    recordIndex: recordIndex,
                    maximum: dataset.metadata.timeStep,
                    actual: duration
                )
            }
            let isShortTerminalTransition = recordIndex == dataset.records.count - 1
                && (record.done == true || record.truncated == true)
            guard abs(duration - dataset.metadata.timeStep) <= tolerance
                    || isShortTerminalTransition else {
                throw ValidationError.incompleteNonTerminalTransition(
                    recordIndex: recordIndex,
                    expected: dataset.metadata.timeStep,
                    actual: duration
                )
            }
            guard let actionObservationState = record.actionObservationState else {
                throw ValidationError.missingActionObservationState(recordIndex: recordIndex)
            }
            guard let actualState = record.actualState else {
                throw ValidationError.missingActualState(recordIndex: recordIndex)
            }
            guard let actionValues = record.actionValues,
                  !actionValues.isEmpty else {
                throw ValidationError.missingPolicyAction(recordIndex: recordIndex)
            }
            if requiresBehaviorStatistics {
                guard record.behaviorMean != nil else {
                    throw ValidationError.missingBehaviorMean(recordIndex: recordIndex)
                }
                guard record.behaviorLogProbability != nil else {
                    throw ValidationError.missingBehaviorLogProbability(recordIndex: recordIndex)
                }
            }
            guard let actuatorCommandValues = record.actuatorCommandValues,
                  !actuatorCommandValues.isEmpty else {
                throw ValidationError.missingAppliedActuatorCommand(recordIndex: recordIndex)
            }
            for (sensorIndex, sensor) in record.sensors.enumerated() {
                guard sensor.timestamp <= actionObservationTime + tolerance else {
                    throw ValidationError.sensorTimestampAfterActionObservation(
                        recordIndex: recordIndex,
                        sensorIndex: sensorIndex,
                        sensorTimestamp: sensor.timestamp,
                        actionObservationTime: actionObservationTime
                    )
                }
            }
            if let previous {
                guard abs(actionObservationTime - previous.time) <= tolerance else {
                    throw ValidationError.transitionTimeDiscontinuity(
                        recordIndex: recordIndex,
                        expected: previous.time,
                        actual: actionObservationTime
                    )
                }
                guard let previousActualState = previous.actualState,
                      previousActualState.count == actionObservationState.count else {
                    throw ValidationError.missingActualState(recordIndex: recordIndex - 1)
                }
                for valueIndex in actionObservationState.indices {
                    let expected = previousActualState[valueIndex]
                    let actual = actionObservationState[valueIndex]
                    guard abs(expected - actual) <= tolerance else {
                        throw ValidationError.transitionStateDiscontinuity(
                            recordIndex: recordIndex,
                            valueIndex: valueIndex,
                            expected: expected,
                            actual: actual
                        )
                    }
                }
            }
            guard !actionObservationState.isEmpty, !actualState.isEmpty else {
                throw ValidationError.missingActionObservationState(recordIndex: recordIndex)
            }
            previous = record
        }
    }

    func validateBehaviorCloningSamples(
        _ dataset: TrainingDataset,
        tolerance: Double
    ) throws {
        guard dataset.metadata.purpose == .behaviorCloning else {
            throw ValidationError.invalidBehaviorCloningPurpose(dataset.metadata.purpose)
        }
        for (recordIndex, record) in dataset.records.enumerated() {
            guard let observationTime = record.actionObservationTime else {
                throw ValidationError.missingActionObservationTime(recordIndex: recordIndex)
            }
            guard abs(observationTime - record.time) <= tolerance else {
                throw ValidationError.behaviorCloningObservationTimeMismatch(
                    recordIndex: recordIndex,
                    observationTime: observationTime,
                    recordTime: record.time
                )
            }
            guard let observationState = record.actionObservationState else {
                throw ValidationError.missingActionObservationState(recordIndex: recordIndex)
            }
            guard let actualState = record.actualState,
                  actualState.count == observationState.count else {
                throw ValidationError.missingActualState(recordIndex: recordIndex)
            }
            for valueIndex in observationState.indices {
                let expected = actualState[valueIndex]
                let actual = observationState[valueIndex]
                guard abs(expected - actual) <= tolerance else {
                    throw ValidationError.behaviorCloningStateMismatch(
                        recordIndex: recordIndex,
                        valueIndex: valueIndex,
                        expected: expected,
                        actual: actual
                    )
                }
            }
            guard let actionValues = record.actionValues,
                  !actionValues.isEmpty else {
                throw ValidationError.missingPolicyAction(recordIndex: recordIndex)
            }
            for (sensorIndex, sensor) in record.sensors.enumerated() {
                guard sensor.timestamp <= observationTime + tolerance else {
                    throw ValidationError.sensorTimestampAfterActionObservation(
                        recordIndex: recordIndex,
                        sensorIndex: sensorIndex,
                        sensorTimestamp: sensor.timestamp,
                        actionObservationTime: observationTime
                    )
                }
            }
        }
    }

}
