import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public extension LearningProjectTemplate {
    static let roArmM1ArmGripperTargetTracking: LearningProjectTemplate = {
        let goal = RoArmM1JointTargetTrainingGoal.canonical
        let profile = TaskEvaluationProfile.roArmM1ArmGripperTargetTracking
        return LearningProjectTemplate(
            templateID: "roarm-m1-arm-gripper-target-tracking-v1",
            displayName: "RoArm M1 Arm and Gripper Target Tracking",
            summary: "Camera-free RoArm M1 training design for proprioceptive arm and gripper target tracking, safe range compliance, HER-style goal relabeling, and dynamic-simulation smoke validation.",
            domain: .manipulator,
            task: goal.task,
            taskProfileID: profile.profileID,
            robotManifest: LearningProjectRobotManifestReference(
                robotManifestID: goal.robotManifestID,
                source: .bundled,
                path: nil,
                contentHash: nil,
                robotClass: .manipulator
            ),
            modelBundlePolicy: LearningProjectModelBundlePolicy(
                sourceCheckpointPolicy: .none,
                requiredBundleSchemaVersion: nil,
                requiresStrictPreflight: true,
                requiresTaskCompatibleDriveCount: true
            ),
            trainingStrategy: LearningProjectTrainingStrategy(
                kind: .supervised,
                evolutionSearchStrategy: nil,
                bootstrapSource: .teacher,
                worldModelUsage: .evaluationAssist,
                usesQualityGate: true,
                usesReinforcementFineTuning: false
            ),
            curriculum: LearningProjectCurriculum(
                suiteIDs: profile.baseEvaluationSuiteIDs,
                seedCount: 1,
                episodesPerSuite: 1,
                populationSize: 100,
                generationLimit: 60,
                convergenceGoal: convergenceGoal(maxGenerationBudget: 60, patienceGenerations: 10),
                eliteCount: 5,
                maxStepCount: 300,
                trainingStages: [
                    LearningProjectTrainingStage(
                        stageID: "teacher-trajectory-bootstrap",
                        kind: .supervised,
                        displayName: "Teacher Trajectory Bootstrap",
                        task: profile.task,
                        taskProfileID: profile.profileID,
                        suiteIDs: profile.baseEvaluationSuiteIDs,
                        seedCount: 1,
                        episodesPerSuite: 1,
                        generationLimit: 1,
                        convergenceGoal: convergenceGoal(maxGenerationBudget: 1, patienceGenerations: 1),
                        executionMode: .sequential,
                        dependsOnStageIDs: [],
                        capabilities: [.sensorIngestion, .stateEstimation, .trajectoryTracking, .safeStop]
                    ),
                    LearningProjectTrainingStage(
                        stageID: "hindsight-goal-relabeling",
                        kind: .supervised,
                        displayName: "Hindsight Goal Relabeling",
                        task: profile.task,
                        taskProfileID: profile.profileID,
                        suiteIDs: profile.baseEvaluationSuiteIDs,
                        seedCount: 1,
                        episodesPerSuite: 1,
                        generationLimit: 1,
                        convergenceGoal: convergenceGoal(maxGenerationBudget: 1, patienceGenerations: 1),
                        executionMode: .sequential,
                        dependsOnStageIDs: ["teacher-trajectory-bootstrap"],
                        capabilities: [.stateEstimation, .trajectoryTracking, .safeStop]
                    ),
                    LearningProjectTrainingStage(
                        stageID: "dynamics-domain-randomization",
                        kind: .stress,
                        displayName: "Dynamics Domain Randomization",
                        task: profile.task,
                        taskProfileID: profile.profileID,
                        suiteIDs: profile.regressionSuiteIDs,
                        seedCount: 2,
                        episodesPerSuite: 1,
                        generationLimit: 60,
                        convergenceGoal: convergenceGoal(maxGenerationBudget: 60, patienceGenerations: 10),
                        executionMode: .parallel,
                        dependsOnStageIDs: ["hindsight-goal-relabeling"],
                        capabilities: [.dynamicsStabilization, .trajectoryTracking, .recoveryBehavior, .safeStop]
                    ),
                    LearningProjectTrainingStage(
                        stageID: "dynamic-simulation-regression",
                        kind: .regression,
                        displayName: "Dynamic Simulation Regression",
                        task: profile.task,
                        taskProfileID: profile.profileID,
                        suiteIDs: profile.regressionSuiteIDs,
                        seedCount: 1,
                        episodesPerSuite: 1,
                        generationLimit: 1,
                        convergenceGoal: validationGateGoal(),
                        executionMode: .sequential,
                        dependsOnStageIDs: ["dynamics-domain-randomization"],
                        capabilities: [.dynamicsStabilization, .trajectoryTracking, .safeStop]
                    )
                ]
            ),
            evaluationGate: LearningProjectEvaluationGate(
                minimumRewardAverage: profile.minimumRewardAverage,
                minimumTaskPassRate: profile.minimumTaskPassRate,
                minimumHoldTimeRatio: profile.minimumHoldTimeRatio,
                maximumAltitudeErrorRatio: profile.maximumAltitudeErrorRatio,
                failOnTruncation: profile.failOnTruncation,
                requiredSafetyGates: [
                    .modelBundleValidated,
                    .deterministicReplayValidated,
                    .scenarioRegressionPassed,
                    .safetyEnvelopeValidated,
                    .telemetryComplete,
                    .artifactLineageComplete
                ]
            ),
            observation: RoArmM1LearningContracts.armGripperTargetTrackingObservationContract(),
            action: RoArmM1LearningContracts.armGripperTargetsActionContract(),
            policy: RoArmM1LearningContracts.armGripperTargetTrackingPolicyContract(),
            compute: localCompute(workerCount: 1, candidateEvaluationConcurrency: 100),
            tags: ["manipulator", "roarm-m1", "arm-gripper", "gripper", "proprioception", "her", "teacher-bootstrap", "design"]
        )
    }()
}
