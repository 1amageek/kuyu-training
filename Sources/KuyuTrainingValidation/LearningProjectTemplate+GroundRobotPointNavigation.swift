import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public extension LearningProjectTemplate {
    static let groundRobotPointNavigation = LearningProjectTemplate(
        templateID: "ground-robot-point-navigation-v1",
        displayName: "Ground Robot Navigation Blueprint",
        summary: "Design blueprint for robot-manifest-driven ground robot navigation, safety gates, and future runtime task profiles.",
        domain: .groundRobot,
        task: "pointNavigation",
        taskProfileID: nil,
        robotManifest: LearningProjectRobotManifestReference(
            robotManifestID: "generated-ground-robot",
            source: .generated,
            path: nil,
            contentHash: nil,
            robotClass: .groundVehicle
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
            suiteIDs: [1],
            seedCount: 3,
            episodesPerSuite: 1,
            populationSize: 100,
            generationLimit: 1_000,
            convergenceGoal: convergenceGoal(maxGenerationBudget: 1_000, patienceGenerations: 50),
            eliteCount: 10,
            maxStepCount: nil
        ),
        evaluationGate: LearningProjectEvaluationGate(
            minimumRewardAverage: nil,
            minimumTaskPassRate: 1,
            minimumHoldTimeRatio: nil,
            maximumAltitudeErrorRatio: nil,
            failOnTruncation: true,
            requiredSafetyGates: [
                .modelBundleValidated,
                .deterministicReplayValidated,
                .safetyEnvelopeValidated,
                .telemetryComplete,
                .artifactLineageComplete
            ]
        ),
        observation: LearningProjectObservationContract(
            schemaID: "ground-robot-navigation-observation-v1",
            channelCount: 6,
            channels: [
                LearningProjectObservationChannel(index: 0, name: "linearVelocityX", unit: "m/s", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 1, name: "linearVelocityY", unit: "m/s", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 2, name: "yawRate", unit: "rad/s", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 3, name: "targetDeltaX", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 4, name: "targetDeltaY", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 5, name: "obstaclePressure", unit: nil, isStateChannel: false, isStressable: true)
            ]
        ),
        action: LearningProjectActionContract(
            schemaID: "differential-drive-v1",
            kind: .continuous,
            driveCount: 2,
            actuatorCount: 2,
            isBounded: true,
            channels: LearningProjectActionContract.boundedChannels(
                names: ["leftWheel", "rightWheel"],
                unit: "normalized",
                lowerBound: -1,
                upperBound: 1,
                transform: .tanh
            )
        ),
        policy: .simpleFeedForward(
            observationDimension: 6,
            actionDimension: 2,
            actionEncoding: .directMotor
        ),
        compute: localCompute(workerCount: 1, candidateEvaluationConcurrency: 100),
        tags: ["ground", "robot", "navigation", "blueprint", "generic"]
    )
}
