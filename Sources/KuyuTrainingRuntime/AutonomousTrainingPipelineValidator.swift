import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation
public struct AutonomousTrainingPipelineValidator: Sendable {
    public init() {}

    public func validate(_ plan: AutonomousTrainingPipelinePlan) throws {
        guard !plan.planID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AutonomousTrainingPipelineValidationError.emptyPlanID
        }
        guard !plan.stages.isEmpty else {
            throw AutonomousTrainingPipelineValidationError.emptyStages
        }

        var stageIDs = Set<String>()
        for (index, stage) in plan.stages.enumerated() {
            let stageID = stage.stageID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stageID.isEmpty else {
                throw AutonomousTrainingPipelineValidationError.emptyStageID(index: index)
            }
            guard stageIDs.insert(stageID).inserted else {
                throw AutonomousTrainingPipelineValidationError.duplicateStageID(stage.stageID)
            }
            guard !stage.taskProfileIDs.isEmpty else {
                throw AutonomousTrainingPipelineValidationError.emptyStageTaskProfiles(stage.stageID)
            }
        }

        guard plan.stages.contains(where: \.producesModelBundle) else {
            throw AutonomousTrainingPipelineValidationError.noBundleProducingStage
        }

        let capabilities = Set(plan.stages.flatMap(\.capabilities)).union(plan.targetCapabilities)
        for capability in Self.requiredCapabilities(for: plan.domain) {
            guard capabilities.contains(capability) else {
                throw AutonomousTrainingPipelineValidationError.missingRequiredCapability(capability)
            }
        }

        let stageKinds = Set(plan.stages.map(\.kind))
        for stage in Self.requiredStages(for: plan.domain) {
            guard stageKinds.contains(stage) else {
                throw AutonomousTrainingPipelineValidationError.missingRequiredStage(stage)
            }
        }

        let terminalGates = Set(plan.terminalGates)
        for gate in Self.requiredTerminalGates(for: plan.domain) {
            guard terminalGates.contains(gate) else {
                throw AutonomousTrainingPipelineValidationError.missingRequiredTerminalGate(gate)
            }
        }

        try requireOrder(.imitation, before: .reinforcement, in: plan.stages)
        try requireOrder(.reinforcement, before: .evolution, in: plan.stages)
        try requireOrder(.evolution, before: .stress, in: plan.stages)
        try requireOrder(.reinforcement, before: .stress, in: plan.stages)
        try requireOrder(.stress, before: .regression, in: plan.stages)
    }

    public static func requiredCapabilities(for domain: AutonomousOperationDomain) -> [AutonomousCapability] {
        switch domain {
        case .automotive:
            return [
                .sensorIngestion, .stateEstimation, .trajectoryTracking,
                .obstacleAvoidance, .faultDetection, .recoveryBehavior,
                .missionExecution, .safeStop, .humanTakeover
            ]
        case .groundRobot:
            return [
                .sensorIngestion, .stateEstimation, .trajectoryTracking,
                .obstacleAvoidance, .faultDetection, .recoveryBehavior,
                .missionExecution, .safeStop, .humanTakeover
            ]
        case .aerialDrone:
            return [
                .sensorIngestion, .stateEstimation, .dynamicsStabilization,
                .trajectoryTracking, .obstacleAvoidance, .faultDetection,
                .recoveryBehavior, .missionExecution, .safeStop, .humanTakeover
            ]
        case .manipulator:
            return [
                .sensorIngestion, .stateEstimation, .trajectoryTracking,
                .obstacleAvoidance, .faultDetection, .recoveryBehavior,
                .safeStop, .humanTakeover
            ]
        }
    }

    public static func requiredStages(for domain: AutonomousOperationDomain) -> [AutonomousTrainingStageKind] {
        switch domain {
        case .automotive, .groundRobot:
            return [.imitation, .reinforcement, .evolution, .worldModel, .stress, .regression, .closedCourse]
        case .aerialDrone:
            return [.imitation, .reinforcement, .evolution, .worldModel, .stress, .regression, .hardwareInTheLoop, .closedCourse]
        case .manipulator:
            return [.imitation, .reinforcement, .evolution, .stress, .regression, .hardwareInTheLoop]
        }
    }

    public static func requiredTerminalGates(for domain: AutonomousOperationDomain) -> [AutonomousSafetyGateKind] {
        var gates: [AutonomousSafetyGateKind] = [
            .modelBundleValidated,
            .deterministicReplayValidated,
            .scenarioRegressionPassed,
            .stressRegressionPassed,
            .safetyEnvelopeValidated,
            .failSafeValidated,
            .humanTakeoverValidated,
            .telemetryComplete,
            .artifactLineageComplete
        ]
        if domain == .aerialDrone || domain == .manipulator {
            gates.append(.hardwareBoundaryValidated)
        }
        return gates
    }

    private func requireOrder(
        _ requiredBefore: AutonomousTrainingStageKind,
        before requiredAfter: AutonomousTrainingStageKind,
        in stages: [AutonomousTrainingStagePlan]
    ) throws {
        guard let beforeIndex = stages.firstIndex(where: { $0.kind == requiredBefore }),
              let afterIndex = stages.firstIndex(where: { $0.kind == requiredAfter }) else {
            return
        }
        guard beforeIndex < afterIndex else {
            throw AutonomousTrainingPipelineValidationError.stageOrderViolation(
                requiredBefore: requiredBefore,
                requiredAfter: requiredAfter
            )
        }
    }
}
