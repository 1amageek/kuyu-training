import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public extension LearningProjectTemplate {
    static let droneAutonomyStarter: LearningProjectTemplate = {
        let liftProfile = TaskEvaluationProfile.lift
        return LearningProjectTemplate(
            templateID: "aerial-drone-autonomy-starter-v1",
            displayName: "Drone Autonomy Starter",
            summary: "Multi-stage drone curriculum for lift, hover, trajectory tracking, disturbance recovery, and final regression gates.",
            domain: .aerialDrone,
            task: "aerialAutonomy",
            taskProfileID: nil,
            robotManifest: LearningProjectRobotManifestReference(
                robotManifestID: "reference-quadrotor",
                source: .bundled,
                path: nil,
                contentHash: nil,
                robotClass: .aerialVehicle
            ),
            modelBundlePolicy: LearningProjectModelBundlePolicy(
                sourceCheckpointPolicy: .createStarter,
                requiredBundleSchemaVersion: nil,
                requiresStrictPreflight: true,
                requiresTaskCompatibleDriveCount: true
            ),
            trainingStrategy: LearningProjectTrainingStrategy(
                kind: .hybrid,
                evolutionSearchStrategy: .qualityDiversity,
                bootstrapSource: .teacher,
                worldModelUsage: .evaluationAssist,
                usesQualityGate: true,
                usesReinforcementFineTuning: true
            ),
            curriculum: LearningProjectCurriculum(
                suiteIDs: [6],
                seedCount: 2,
                episodesPerSuite: 1,
                populationSize: 100,
                generationLimit: 1_000,
                convergenceGoal: convergenceGoal(maxGenerationBudget: 1_000, patienceGenerations: 50),
                eliteCount: 10,
                maxStepCount: nil,
                trainingStages: [
                    LearningProjectTrainingStage(
                        stageID: "lift-foundation",
                        kind: .reinforcement,
                        displayName: "Lift Foundation",
                        task: liftProfile.task,
                        taskProfileID: liftProfile.profileID,
                        suiteIDs: [6],
                        seedCount: 2,
                        episodesPerSuite: 1,
                        generationLimit: 1_000,
                        convergenceGoal: convergenceGoal(maxGenerationBudget: 1_000, patienceGenerations: 50),
                        executionMode: .sequential,
                        dependsOnStageIDs: [],
                        capabilities: [.sensorIngestion, .dynamicsStabilization, .safeStop]
                    ),
                    LearningProjectTrainingStage(
                        stageID: "hover-stabilization",
                        kind: .reinforcement,
                        displayName: "Hover Stabilization",
                        task: "hoverStabilization",
                        taskProfileID: nil,
                        suiteIDs: [1],
                        seedCount: 3,
                        episodesPerSuite: 1,
                        generationLimit: 1_500,
                        convergenceGoal: convergenceGoal(maxGenerationBudget: 1_500, patienceGenerations: 25),
                        executionMode: .sequential,
                        dependsOnStageIDs: ["lift-foundation"],
                        capabilities: [.stateEstimation, .dynamicsStabilization, .trajectoryTracking]
                    ),
                    LearningProjectTrainingStage(
                        stageID: "trajectory-tracking",
                        kind: .evolution,
                        displayName: "Trajectory Tracking",
                        task: "trajectoryTracking",
                        taskProfileID: nil,
                        suiteIDs: [1, 2],
                        seedCount: 4,
                        episodesPerSuite: 1,
                        generationLimit: 2_000,
                        convergenceGoal: convergenceGoal(maxGenerationBudget: 2_000, patienceGenerations: 30),
                        executionMode: .parallel,
                        dependsOnStageIDs: ["hover-stabilization"],
                        capabilities: [.trajectoryTracking, .obstacleAvoidance, .missionExecution]
                    ),
                    LearningProjectTrainingStage(
                        stageID: "world-model-prediction",
                        kind: .worldModel,
                        displayName: "Physics-Grounded World Model",
                        task: "worldModelPrediction",
                        taskProfileID: nil,
                        suiteIDs: [6, 7, 8],
                        seedCount: 4,
                        episodesPerSuite: 1,
                        generationLimit: 1,
                        convergenceGoal: validationGateGoal(),
                        executionMode: .sequential,
                        dependsOnStageIDs: ["trajectory-tracking"],
                        capabilities: [.stateEstimation, .faultDetection]
                    ),
                    LearningProjectTrainingStage(
                        stageID: "disturbance-recovery",
                        kind: .stress,
                        displayName: "Disturbance Recovery",
                        task: "disturbanceRecovery",
                        taskProfileID: nil,
                        suiteIDs: [6, 7, 8],
                        seedCount: 4,
                        episodesPerSuite: 1,
                        generationLimit: 2_000,
                        convergenceGoal: convergenceGoal(maxGenerationBudget: 2_000, patienceGenerations: 30),
                        executionMode: .parallel,
                        dependsOnStageIDs: ["hover-stabilization", "world-model-prediction"],
                        capabilities: [.faultDetection, .recoveryBehavior, .safeStop]
                    ),
                    LearningProjectTrainingStage(
                        stageID: "full-regression",
                        kind: .regression,
                        displayName: "Full Regression Gate",
                        task: "aerialRegression",
                        taskProfileID: nil,
                        suiteIDs: [6, 7, 8],
                        seedCount: 4,
                        episodesPerSuite: 1,
                        generationLimit: 1,
                        convergenceGoal: validationGateGoal(),
                        executionMode: .sequential,
                        dependsOnStageIDs: ["trajectory-tracking", "disturbance-recovery"],
                        capabilities: [.dynamicsStabilization, .trajectoryTracking, .recoveryBehavior, .safeStop]
                    )
                ]
            ),
            evaluationGate: .from(profile: liftProfile),
            observation: ReferenceQuadrotorLearningContracts.temporalCTBRObservationContract(),
            action: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
            policy: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(),
            compute: LearningProjectComputeProfile(
                preset: .local,
                workerCount: 1,
                candidateEvaluationConcurrency: 100,
                requiresMetal: true,
                targetAccelerator: .metal,
                usesMachineOptimizedParallelism: true,
                minimumPopulationSize: 100,
                estimatedDiskBytes: nil
            ),
            tags: ["aerial", "drone", "autonomy", "starter", "hybrid", "multi-stage"]
        )
    }()
}
