import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation
public struct AutonomousTrainingPipelineFactory: Sendable {
    public init() {}

    public func defaultPlan(
        domain: AutonomousOperationDomain,
        taskProfileIDs: [String]
    ) -> AutonomousTrainingPipelinePlan {
        let targetCapabilities = AutonomousTrainingPipelineValidator.requiredCapabilities(for: domain)
        var stages = [
            AutonomousTrainingStagePlan(
                stageID: "imitation-bootstrap",
                kind: .imitation,
                taskProfileIDs: taskProfileIDs,
                capabilities: [.sensorIngestion, .stateEstimation, .dynamicsStabilization],
                requiredExitGates: [.modelBundleValidated, .artifactLineageComplete],
                producesModelBundle: true
            ),
            AutonomousTrainingStagePlan(
                stageID: "closed-loop-reinforcement",
                kind: .reinforcement,
                taskProfileIDs: taskProfileIDs,
                capabilities: [.trajectoryTracking, .safeStop],
                requiredEntryGates: [.modelBundleValidated],
                requiredExitGates: [.modelBundleValidated, .scenarioRegressionPassed],
                producesModelBundle: true
            )
        ]

        stages.append(AutonomousTrainingStagePlan(
            stageID: "evolution-search",
            kind: .evolution,
            taskProfileIDs: taskProfileIDs,
            capabilities: evolutionCapabilities(for: domain),
            requiredEntryGates: [.modelBundleValidated],
            requiredExitGates: [.modelBundleValidated, .scenarioRegressionPassed],
            producesModelBundle: true
        ))

        stages.append(contentsOf: [
            AutonomousTrainingStagePlan(
                stageID: "world-model-prediction",
                kind: .worldModel,
                taskProfileIDs: taskProfileIDs,
                capabilities: [.stateEstimation, .obstacleAvoidance, .faultDetection],
                requiredEntryGates: [.modelBundleValidated],
                requiredExitGates: [
                    .deterministicReplayValidated,
                    .telemetryComplete,
                    .artifactLineageComplete,
                ],
                producesModelBundle: false
            ),
            AutonomousTrainingStagePlan(
                stageID: "stress-and-rare-case",
                kind: .stress,
                taskProfileIDs: taskProfileIDs,
                capabilities: [.faultDetection, .recoveryBehavior, .safeStop, .humanTakeover],
                requiredEntryGates: [.scenarioRegressionPassed],
                requiredExitGates: [.stressRegressionPassed, .failSafeValidated, .humanTakeoverValidated],
                producesModelBundle: true
            ),
            AutonomousTrainingStagePlan(
                stageID: "full-regression",
                kind: .regression,
                taskProfileIDs: taskProfileIDs,
                capabilities: targetCapabilities,
                requiredEntryGates: [.stressRegressionPassed],
                requiredExitGates: [.scenarioRegressionPassed, .deterministicReplayValidated, .safetyEnvelopeValidated],
                producesModelBundle: false
            )
        ])

        if domain == .aerialDrone || domain == .manipulator {
            stages.append(AutonomousTrainingStagePlan(
                stageID: "hardware-in-the-loop",
                kind: .hardwareInTheLoop,
                taskProfileIDs: taskProfileIDs,
                capabilities: [.faultDetection, .safeStop, .humanTakeover],
                requiredEntryGates: [.scenarioRegressionPassed, .stressRegressionPassed],
                requiredExitGates: [.hardwareBoundaryValidated, .telemetryComplete],
                producesModelBundle: false
            ))
        }

        stages.append(AutonomousTrainingStagePlan(
            stageID: "closed-course-validation",
            kind: .closedCourse,
            taskProfileIDs: taskProfileIDs,
            capabilities: targetCapabilities,
            requiredEntryGates: [.scenarioRegressionPassed, .stressRegressionPassed],
            requiredExitGates: AutonomousTrainingPipelineValidator.requiredTerminalGates(for: domain),
            producesModelBundle: false
        ))

        return AutonomousTrainingPipelinePlan(
            planID: "\(domain.rawValue)-autonomy-v1",
            domain: domain,
            targetCapabilities: targetCapabilities,
            stages: stages,
            terminalGates: AutonomousTrainingPipelineValidator.requiredTerminalGates(for: domain)
        )
    }

    private func evolutionCapabilities(for domain: AutonomousOperationDomain) -> [AutonomousCapability] {
        switch domain {
        case .aerialDrone:
            return [.dynamicsStabilization, .trajectoryTracking, .recoveryBehavior]
        case .automotive, .groundRobot:
            return [.trajectoryTracking, .obstacleAvoidance, .recoveryBehavior]
        case .manipulator:
            return [.trajectoryTracking, .obstacleAvoidance, .recoveryBehavior]
        }
    }
}
