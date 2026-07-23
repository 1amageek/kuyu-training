import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public extension LearningProjectTemplate {
    static let automotiveLaneKeeping = LearningProjectTemplate(
        templateID: "automotive-lane-keeping-v1",
        displayName: "Automotive Lane Keeping Blueprint",
        summary: "Design blueprint for lane keeping, speed tracking, safety envelope validation, and future vehicle task profiles.",
        domain: .automotive,
        task: "laneKeeping",
        taskProfileID: nil,
        robotManifest: LearningProjectRobotManifestReference(
            robotManifestID: "generated-road-vehicle",
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
            suiteIDs: [1, 2],
            seedCount: 4,
            episodesPerSuite: 1,
            populationSize: 100,
            generationLimit: 2_000,
            convergenceGoal: convergenceGoal(maxGenerationBudget: 2_000, patienceGenerations: 70),
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
                .scenarioRegressionPassed,
                .stressRegressionPassed,
                .safetyEnvelopeValidated,
                .humanTakeoverValidated,
                .telemetryComplete,
                .artifactLineageComplete
            ]
        ),
        observation: LearningProjectObservationContract(
            schemaID: "automotive-lane-keeping-observation-v1",
            channelCount: 8,
            channels: [
                LearningProjectObservationChannel(index: 0, name: "speed", unit: "m/s", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 1, name: "yawRate", unit: "rad/s", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 2, name: "lateralOffset", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 3, name: "headingError", unit: "rad", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 4, name: "curvatureAhead", unit: "1/m", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 5, name: "leadVehicleDistance", unit: "m", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 6, name: "laneConfidence", unit: nil, isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 7, name: "constraintPressure", unit: nil, isStateChannel: false, isStressable: true)
            ]
        ),
        action: LearningProjectActionContract(
            schemaID: "vehicle-steer-throttle-brake-v1",
            kind: .continuous,
            driveCount: 3,
            actuatorCount: 3,
            isBounded: true,
            channels: [
                LearningProjectActionChannel(
                    index: 0,
                    name: "steering",
                    unit: "normalized",
                    normalizedLowerBound: -1,
                    normalizedUpperBound: 1,
                    outputTransform: .tanh
                ),
                LearningProjectActionChannel(
                    index: 1,
                    name: "throttle",
                    unit: "normalized",
                    normalizedLowerBound: 0,
                    normalizedUpperBound: 1,
                    outputTransform: .sigmoid
                ),
                LearningProjectActionChannel(
                    index: 2,
                    name: "brake",
                    unit: "normalized",
                    normalizedLowerBound: 0,
                    normalizedUpperBound: 1,
                    outputTransform: .sigmoid
                )
            ]
        ),
        policy: .simpleFeedForward(
            observationDimension: 8,
            actionDimension: 3,
            actionEncoding: .vehicleSteerThrottleBrake
        ),
        compute: localCompute(workerCount: 2, candidateEvaluationConcurrency: 2),
        tags: ["automotive", "lane-keeping", "safety", "blueprint", "hybrid"]
    )
}
