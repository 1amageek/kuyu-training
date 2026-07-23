import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public extension LearningProjectTemplate {
    static let manipulatorPickAndPlace = LearningProjectTemplate(
        templateID: "manipulator-pick-and-place-v1",
        displayName: "Manipulator Pick-and-Place Blueprint",
        summary: "Design blueprint for reaching, grasping, lifting, placing, and future manipulation task profiles.",
        domain: .manipulator,
        task: "pickAndPlace",
        taskProfileID: nil,
        robotManifest: LearningProjectRobotManifestReference(
            robotManifestID: "generated-manipulator",
            source: .generated,
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
            kind: .hybrid,
            evolutionSearchStrategy: .qualityDiversity,
            bootstrapSource: .demonstration,
            worldModelUsage: .evaluationAssist,
            usesQualityGate: true,
            usesReinforcementFineTuning: true
        ),
        curriculum: LearningProjectCurriculum(
            suiteIDs: [1],
            seedCount: 3,
            episodesPerSuite: 1,
            populationSize: 100,
            generationLimit: 1_500,
            convergenceGoal: convergenceGoal(maxGenerationBudget: 1_500, patienceGenerations: 60),
            eliteCount: 10,
            maxStepCount: nil
        ),
        evaluationGate: genericSafetyGate(failOnTruncation: true),
        observation: LearningProjectObservationContract(
            schemaID: "manipulator-pick-place-observation-v1",
            channelCount: 8,
            channels: [
                LearningProjectObservationChannel(index: 0, name: "endEffectorDeltaX", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 1, name: "endEffectorDeltaY", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 2, name: "endEffectorDeltaZ", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 3, name: "objectDeltaX", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 4, name: "objectDeltaY", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 5, name: "objectDeltaZ", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 6, name: "gripForce", unit: "N", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 7, name: "contactState", unit: nil, isStateChannel: false, isStressable: true)
            ]
        ),
        action: LearningProjectActionContract(
            schemaID: "manipulator-joint-and-gripper-v1",
            kind: .continuous,
            driveCount: 7,
            actuatorCount: 7,
            isBounded: true,
            channels: LearningProjectActionContract.indexedBoundedChannels(
                prefix: "manipulatorTarget",
                count: 7,
                unit: "normalized",
                lowerBound: -1,
                upperBound: 1,
                transform: .tanh
            )
        ),
        policy: .simpleFeedForward(
            observationDimension: 8,
            actionDimension: 7,
            actionEncoding: .jointTargets
        ),
        compute: localCompute(workerCount: 2, candidateEvaluationConcurrency: 2),
        tags: ["manipulator", "pick", "place", "grasp", "blueprint", "hybrid"]
    )
}
