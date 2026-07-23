import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public extension LearningProjectTemplate {
    static let leggedRobotLocomotion = LearningProjectTemplate(
        templateID: "legged-robot-locomotion-v1",
        displayName: "Legged Robot Locomotion Blueprint",
        summary: "Design blueprint for gait stabilization, balance, terrain stress evaluation, and future locomotion task profiles.",
        domain: .groundRobot,
        task: "leggedLocomotion",
        taskProfileID: nil,
        robotManifest: LearningProjectRobotManifestReference(
            robotManifestID: "generated-legged-robot",
            source: .generated,
            path: nil,
            contentHash: nil,
            robotClass: .leggedRobot
        ),
        modelBundlePolicy: LearningProjectModelBundlePolicy(
            sourceCheckpointPolicy: .none,
            requiredBundleSchemaVersion: nil,
            requiresStrictPreflight: true,
            requiresTaskCompatibleDriveCount: true
        ),
        trainingStrategy: LearningProjectTrainingStrategy(
            kind: .hybrid,
            evolutionSearchStrategy: .qualityDiversity,
            bootstrapSource: .demonstration,
            worldModelUsage: .imaginationAssist,
            usesQualityGate: true,
            usesReinforcementFineTuning: true
        ),
        curriculum: LearningProjectCurriculum(
            suiteIDs: [1, 2],
            seedCount: 4,
            episodesPerSuite: 1,
            populationSize: 100,
            generationLimit: 2_000,
            convergenceGoal: convergenceGoal(maxGenerationBudget: 2_000, patienceGenerations: 70),
            eliteCount: 10,
            maxStepCount: nil
        ),
        evaluationGate: genericSafetyGate(failOnTruncation: true),
        observation: LearningProjectObservationContract(
            schemaID: "legged-locomotion-observation-v1",
            channelCount: 8,
            channels: [
                LearningProjectObservationChannel(index: 0, name: "bodyRoll", unit: "rad", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 1, name: "bodyPitch", unit: "rad", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 2, name: "bodyYawRate", unit: "rad/s", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 3, name: "linearVelocityX", unit: "m/s", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 4, name: "linearVelocityY", unit: "m/s", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 5, name: "height", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 6, name: "footContactPressure", unit: nil, isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 7, name: "terrainSlope", unit: "rad", isStateChannel: false, isStressable: true)
            ]
        ),
        action: LearningProjectActionContract(
            schemaID: "legged-joint-targets-v1",
            kind: .continuous,
            driveCount: 12,
            actuatorCount: 12,
            isBounded: true,
            channels: LearningProjectActionContract.indexedBoundedChannels(
                prefix: "jointTarget",
                count: 12,
                unit: "normalized",
                lowerBound: -1,
                upperBound: 1,
                transform: .tanh
            )
        ),
        policy: .simpleFeedForward(
            observationDimension: 8,
            actionDimension: 12,
            actionEncoding: .jointTargets
        ),
        compute: localCompute(workerCount: 2, candidateEvaluationConcurrency: 2),
        tags: ["ground", "legged", "locomotion", "balance", "blueprint", "hybrid"]
    )
}
