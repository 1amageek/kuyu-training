import Foundation

public struct TrainingRunInspectionArtifactValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable {
        case unsupportedSchemaVersion(Int)
        case emptyField(String)
        case invalidIteration(Int)
        case invalidSampleRate(Double)
        case invalidProfileContract(String)
        case invalidExecutionContract(String)
        case emptyScenarios
        case duplicateScenario(String)
        case invalidSourceStepCount(scenario: String, count: Int)
        case invalidSourceTimeStep(scenario: String, value: Double)
        case invalidSourceCadence(scenario: String)
        case emptySamples(String)
        case nonMonotonicSampleTime(scenario: String, previous: Double, current: Double)
        case invalidSafetyCost(scenario: String, stepIndex: UInt64, value: Double)
        case emptyConstraintViolationID(scenario: String, stepIndex: UInt64)
        case duplicateConstraintViolationID(scenario: String, stepIndex: UInt64, id: String)
        case invalidFailureTime(scenario: String, value: Double)
        case failureBeyondTrace(scenario: String, failureTime: Double, finalSampleTime: Double)
    }

    public init() {}

    public func validate(_ artifact: TrainingRunInspectionArtifact) throws {
        guard artifact.schemaVersion == TrainingRunInspectionArtifact.currentSchemaVersion else {
            throw ValidationError.unsupportedSchemaVersion(artifact.schemaVersion)
        }
        try validateRequired(artifact.runID, field: "runID")
        if let iteration = artifact.iteration, iteration < 0 {
            throw ValidationError.invalidIteration(iteration)
        }
        try validateRequired(artifact.candidateID, field: "candidateID")
        try validateRequired(artifact.checkpointPath, field: "checkpointPath")
        if let checkpointDigest = artifact.checkpointDigest {
            try validateRequired(checkpointDigest, field: "checkpointDigest")
        }
        do {
            try TaskEvaluationProfileContractValidator().validate(artifact.profile)
        } catch let error as TaskEvaluationProfileContractValidationError {
            throw ValidationError.invalidProfileContract(error.description)
        }
        try validateExecution(artifact.execution)
        guard artifact.targetSampleRateHz.isFinite, artifact.targetSampleRateHz > 0 else {
            throw ValidationError.invalidSampleRate(artifact.targetSampleRateHz)
        }
        if let descriptor = artifact.safetyCostDescriptor {
            try validateRequired(descriptor.id, field: "safetyCostDescriptor.id")
            try validateRequired(descriptor.version, field: "safetyCostDescriptor.version")
            try validateRequired(descriptor.configHash, field: "safetyCostDescriptor.configHash")
        }
        guard !artifact.scenarios.isEmpty else {
            throw ValidationError.emptyScenarios
        }

        var identities = Set<String>()
        for scenario in artifact.scenarios {
            try validateRequired(scenario.scenarioID, field: "scenarioID")
            try validateRequired(scenario.configHash, field: "scenario.configHash")
            guard identities.insert(scenario.identity).inserted else {
                throw ValidationError.duplicateScenario(scenario.identity)
            }
            try validate(scenario)
        }
    }

    private func validate(_ scenario: TrainingRunInspectionArtifact.Scenario) throws {
        guard scenario.sourceStepCount > 0 else {
            throw ValidationError.invalidSourceStepCount(
                scenario: scenario.identity,
                count: scenario.sourceStepCount
            )
        }
        guard scenario.sourceTimeStep.isFinite, scenario.sourceTimeStep > 0 else {
            throw ValidationError.invalidSourceTimeStep(
                scenario: scenario.identity,
                value: scenario.sourceTimeStep
            )
        }
        guard scenario.sourcePhysicsTimeStep.isFinite,
              scenario.sourcePhysicsTimeStep > 0,
              scenario.sourceControlPeriodSteps > 0 else {
            throw ValidationError.invalidSourceCadence(scenario: scenario.identity)
        }
        let eventPeriodSteps = scenario.sourceTimeStep / scenario.sourcePhysicsTimeStep
        guard eventPeriodSteps.isFinite,
              eventPeriodSteps >= 1 - 1e-9,
              eventPeriodSteps <= Double(scenario.sourceControlPeriodSteps) + 1e-9,
              abs(eventPeriodSteps.rounded() - eventPeriodSteps) <= 1e-9 else {
            throw ValidationError.invalidSourceCadence(scenario: scenario.identity)
        }
        guard !scenario.samples.isEmpty else {
            throw ValidationError.emptySamples(scenario.identity)
        }

        var previousTime: Double?
        for sample in scenario.samples {
            let time = sample.step.time.time
            if let previousTime, time <= previousTime {
                throw ValidationError.nonMonotonicSampleTime(
                    scenario: scenario.identity,
                    previous: previousTime,
                    current: time
                )
            }
            previousTime = time
            if let safetyCost = sample.safetyCost,
               (!safetyCost.isFinite || safetyCost < 0) {
                throw ValidationError.invalidSafetyCost(
                    scenario: scenario.identity,
                    stepIndex: sample.step.time.stepIndex,
                    value: safetyCost
                )
            }
            var violationIDs = Set<String>()
            for id in sample.constraintViolationIDs {
                guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ValidationError.emptyConstraintViolationID(
                        scenario: scenario.identity,
                        stepIndex: sample.step.time.stepIndex
                    )
                }
                guard violationIDs.insert(id).inserted else {
                    throw ValidationError.duplicateConstraintViolationID(
                        scenario: scenario.identity,
                        stepIndex: sample.step.time.stepIndex,
                        id: id
                    )
                }
            }
        }

        if let failureTime = scenario.failureTime {
            guard failureTime.isFinite, failureTime >= 0 else {
                throw ValidationError.invalidFailureTime(
                    scenario: scenario.identity,
                    value: failureTime
                )
            }
            let finalSampleTime = scenario.samples[scenario.samples.count - 1].step.time.time
            guard failureTime <= finalSampleTime + scenario.sourceTimeStep else {
                throw ValidationError.failureBeyondTrace(
                    scenario: scenario.identity,
                    failureTime: failureTime,
                    finalSampleTime: finalSampleTime
                )
            }
        }
    }

    private func validateExecution(
        _ descriptor: TrainingRunInspectionArtifact.ExecutionDescriptor
    ) throws {
        try validateRequired(descriptor.actionContractSchemaID, field: "execution.actionContractSchemaID")
        guard descriptor.motorNerveSettings.rateLimitPerSecond.isFinite,
              descriptor.motorNerveSettings.rateLimitPerSecond > 0 else {
            throw ValidationError.invalidExecutionContract("motorNerveSettings.rateLimitPerSecond")
        }
        if let smoothing = descriptor.motorNerveSettings.smoothingTimeConstant,
           (!smoothing.isFinite || smoothing <= 0) {
            throw ValidationError.invalidExecutionContract("motorNerveSettings.smoothingTimeConstant")
        }
        guard descriptor.schedule.sensor.periodSteps == 1,
              descriptor.schedule.motorNerve?.periodSteps == descriptor.schedule.cut.periodSteps else {
            throw ValidationError.invalidExecutionContract("schedule")
        }
    }

    private func validateRequired(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyField(field)
        }
    }
}
