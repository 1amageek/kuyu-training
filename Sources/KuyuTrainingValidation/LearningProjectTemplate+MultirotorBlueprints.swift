import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public extension LearningProjectTemplate {
    static let droneHoverStabilization = LearningProjectTemplate(
        templateID: "aerial-drone-hover-stabilization-v1",
        displayName: "Drone Hover Stabilization Blueprint",
        summary: "Design blueprint for hover stabilization after the corresponding task profile and runtime stage are available.",
        domain: .aerialDrone,
        task: "hoverStabilization",
        taskProfileID: nil,
        robotManifest: LearningProjectRobotManifestReference(
            robotManifestID: "generated-multirotor",
            source: .generated,
            path: nil,
            contentHash: nil,
            robotClass: .aerialVehicle
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
            bootstrapSource: .teacher,
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
        observation: multirotorBlueprintObservationContract(
            schemaID: "multirotor-hover-observation-v1"
        ),
        action: multirotorBlueprintDirectDriveActionContract(),
        policy: .simpleFeedForward(
            observationDimension: 16,
            actionDimension: 4,
            actionEncoding: .directMotor
        ),
        compute: localCompute(workerCount: 2, candidateEvaluationConcurrency: 2),
        tags: ["aerial", "drone", "hover", "stabilization", "blueprint", "hybrid"]
    )

    static let droneWaypointNavigation = LearningProjectTemplate(
        templateID: "aerial-drone-waypoint-navigation-v1",
        displayName: "Drone Waypoint Navigation Blueprint",
        summary: "Design blueprint for waypoint tracking after hover stability and navigation task profiles are implemented.",
        domain: .aerialDrone,
        task: "waypointNavigation",
        taskProfileID: nil,
        robotManifest: LearningProjectRobotManifestReference(
            robotManifestID: "generated-multirotor-navigation",
            source: .generated,
            path: nil,
            contentHash: nil,
            robotClass: .aerialVehicle
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
        observation: multirotorBlueprintObservationContract(
            schemaID: "multirotor-waypoint-observation-v1"
        ),
        action: multirotorBlueprintDirectDriveActionContract(),
        policy: .simpleFeedForward(
            observationDimension: 16,
            actionDimension: 4,
            actionEncoding: .directMotor
        ),
        compute: localCompute(workerCount: 2, candidateEvaluationConcurrency: 2),
        tags: ["aerial", "drone", "waypoint", "navigation", "blueprint", "hybrid"]
    )
}
