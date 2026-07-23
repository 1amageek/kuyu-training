import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public extension LearningProjectTemplate {
    static let singlePropLiftRecovery: LearningProjectTemplate = {
        let profile = TaskEvaluationProfile.singleLift
        return LearningProjectTemplate(
            templateID: "aerial-single-prop-lift-recovery-v1",
            displayName: "Single Prop Lift Diagnostic",
            summary: "Runnable one-drive diagnostic fixture for lift recovery, artifact gates, and task-specific quality validation.",
            domain: .aerialDrone,
            task: profile.task,
            taskProfileID: profile.profileID,
            robotManifest: LearningProjectRobotManifestReference(
                robotManifestID: "reference-single-prop",
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
                kind: .genetic,
                evolutionSearchStrategy: .qualityDiversity,
                bootstrapSource: .teacher,
                worldModelUsage: .disabled,
                usesQualityGate: true,
                usesReinforcementFineTuning: false
            ),
            curriculum: LearningProjectCurriculum(
                suiteIDs: profile.regressionSuiteIDs,
                seedCount: 3,
                episodesPerSuite: 1,
                populationSize: 100,
                generationLimit: 1_000,
                convergenceGoal: convergenceGoal(maxGenerationBudget: 1_000, patienceGenerations: 50),
                eliteCount: 10,
                maxStepCount: nil,
                trainingStages: [
                    LearningProjectTrainingStage(
                        stageID: "single-prop-lift-recovery",
                        kind: .evolution,
                        displayName: "Single Prop Lift Diagnostic",
                        task: profile.task,
                        taskProfileID: profile.profileID,
                        suiteIDs: profile.regressionSuiteIDs,
                        seedCount: 3,
                        episodesPerSuite: 1,
                        generationLimit: 1_000,
                        convergenceGoal: convergenceGoal(maxGenerationBudget: 1_000, patienceGenerations: 50),
                        executionMode: .sequential,
                        dependsOnStageIDs: [],
                        capabilities: [.sensorIngestion, .dynamicsStabilization, .recoveryBehavior, .safeStop]
                    ),
                    LearningProjectTrainingStage(
                        stageID: "single-prop-regression",
                        kind: .regression,
                        displayName: "Single Prop Regression Gate",
                        task: profile.task,
                        taskProfileID: profile.profileID,
                        suiteIDs: profile.regressionSuiteIDs,
                        seedCount: 3,
                        episodesPerSuite: 1,
                        generationLimit: 1,
                        convergenceGoal: validationGateGoal(),
                        executionMode: .sequential,
                        dependsOnStageIDs: ["single-prop-lift-recovery"],
                        capabilities: [.dynamicsStabilization, .recoveryBehavior, .safeStop]
                    )
                ]
            ),
            evaluationGate: .from(profile: profile),
            observation: ReferenceQuadrotorLearningContracts.liftObservationContract(),
            action: ReferenceQuadrotorLearningContracts.singlePropellerActionContract(),
            policy: .simpleFeedForward(
                observationDimension: ReferenceQuadrotorLearningContracts.liftObservationContract().channelCount,
                actionDimension: 1,
                actionEncoding: .directMotor
            ),
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
            tags: ["aerial", "drone", "single-prop", "diagnostic", "recovery"]
        )
    }()
}
