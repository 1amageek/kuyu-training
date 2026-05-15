import Foundation

public struct LearningProjectTemplateCatalog: Sendable {
    public let templates: [LearningProjectTemplate]

    public init(templates: [LearningProjectTemplate] = LearningProjectTemplateCatalog.defaultTemplates) {
        self.templates = templates
    }

    public func template(id: String) -> LearningProjectTemplate? {
        templates.first { $0.templateID == id }
    }

    public static let defaultTemplates: [LearningProjectTemplate] = [
        .droneAutonomyStarter,
        .singlePropLiftRecovery,
        .droneHoverStabilization,
        .droneWaypointNavigation,
        .groundRobotPointNavigation,
        .leggedRobotLocomotion,
        .manipulatorPickAndPlace,
        .automotiveLaneKeeping
    ]
}

public extension LearningProjectTemplate {
    static let droneAutonomyStarter: LearningProjectTemplate = {
        let liftProfile = knownTaskEvaluationProfile(task: "lift")
        return LearningProjectTemplate(
            templateID: "aerial-drone-autonomy-starter-v1",
            displayName: "Drone Autonomy Starter",
            summary: "Multi-stage drone curriculum for lift, hover, trajectory tracking, disturbance recovery, and final regression gates.",
            domain: .aerialDrone,
            task: "aerialAutonomy",
            taskProfileID: nil,
            descriptor: LearningProjectDescriptorReference(
                descriptorID: "reference-quadrotor",
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
                        dependsOnStageIDs: ["hover-stabilization"],
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
            observation: .referenceQuadrotorTemporalCTBR(),
            action: .referenceQuadrotorBodyRateControl(),
            policy: .referenceQuadrotorTemporalCTBR(),
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

    static let singlePropLiftRecovery: LearningProjectTemplate = {
        let profile = knownTaskEvaluationProfile(task: "singleLift")
        return LearningProjectTemplate(
            templateID: "aerial-single-prop-lift-recovery-v1",
            displayName: "Single Prop Lift Recovery",
            summary: "Aerial recovery template for one-drive lift behavior and task-specific quality gates.",
            domain: .aerialDrone,
            task: profile.task,
            taskProfileID: profile.profileID,
            descriptor: LearningProjectDescriptorReference(
                descriptorID: "reference-single-prop",
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
                        displayName: "Single Prop Lift Recovery",
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
            observation: .referenceQuadrotorLift(),
            action: LearningProjectActionContract(
                schemaID: "single-prop-drive-v1",
                kind: .continuous,
                driveCount: 1,
                actuatorCount: 1,
                isBounded: true
            ),
            policy: .simpleFeedForward(
                observationDimension: LearningProjectObservationContract.referenceQuadrotorLift().channelCount,
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
            tags: ["aerial", "drone", "single-prop", "recovery"]
        )
    }()

    static let groundRobotPointNavigation = LearningProjectTemplate(
        templateID: "ground-robot-point-navigation-v1",
        displayName: "Ground Robot Point Navigation",
        summary: "Generic ground robot navigation template for future descriptor-driven tasks.",
        domain: .groundRobot,
        task: "pointNavigation",
        taskProfileID: nil,
        descriptor: LearningProjectDescriptorReference(
            descriptorID: "generated-ground-robot",
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
            isBounded: true
        ),
        policy: .simpleFeedForward(
            observationDimension: 6,
            actionDimension: 2,
            actionEncoding: .directMotor
        ),
        compute: localCompute(workerCount: 1, candidateEvaluationConcurrency: 100),
        tags: ["ground", "robot", "navigation", "generic"]
    )

    static let droneHoverStabilization = LearningProjectTemplate(
        templateID: "aerial-drone-hover-stabilization-v1",
        displayName: "Aerial Drone Hover Stabilization",
        summary: "Generic aerial hover template for stabilizing altitude, attitude, and bounded motor output before navigation tasks.",
        domain: .aerialDrone,
        task: "hoverStabilization",
        taskProfileID: nil,
        descriptor: LearningProjectDescriptorReference(
            descriptorID: "generated-multirotor",
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
        observation: .referenceQuadrotorTemporalCTBR(),
        action: .referenceQuadrotorBodyRateControl(),
        policy: .referenceQuadrotorTemporalCTBR(),
        compute: localCompute(workerCount: 2, candidateEvaluationConcurrency: 2),
        tags: ["aerial", "drone", "hover", "stabilization", "hybrid"]
    )

    static let droneWaypointNavigation = LearningProjectTemplate(
        templateID: "aerial-drone-waypoint-navigation-v1",
        displayName: "Aerial Drone Waypoint Navigation",
        summary: "Generic aerial waypoint template for target tracking after hover stability has been validated.",
        domain: .aerialDrone,
        task: "waypointNavigation",
        taskProfileID: nil,
        descriptor: LearningProjectDescriptorReference(
            descriptorID: "generated-multirotor-navigation",
            source: .generated,
            path: nil,
            contentHash: nil,
            robotClass: .aerialVehicle
        ),
        modelBundlePolicy: LearningProjectModelBundlePolicy(
            sourceCheckpointPolicy: .optionalExisting,
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
        observation: .referenceQuadrotorTemporalCTBR(),
        action: .referenceQuadrotorBodyRateControl(),
        policy: .referenceQuadrotorTemporalCTBR(),
        compute: localCompute(workerCount: 2, candidateEvaluationConcurrency: 2),
        tags: ["aerial", "drone", "waypoint", "navigation", "hybrid"]
    )

    static let leggedRobotLocomotion = LearningProjectTemplate(
        templateID: "legged-robot-locomotion-v1",
        displayName: "Legged Robot Locomotion",
        summary: "Generic legged locomotion template for gait stabilization, balance, and terrain stress evaluation.",
        domain: .groundRobot,
        task: "leggedLocomotion",
        taskProfileID: nil,
        descriptor: LearningProjectDescriptorReference(
            descriptorID: "generated-legged-robot",
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
            isBounded: true
        ),
        policy: .simpleFeedForward(
            observationDimension: 8,
            actionDimension: 12,
            actionEncoding: .jointTargets
        ),
        compute: localCompute(workerCount: 2, candidateEvaluationConcurrency: 2),
        tags: ["ground", "legged", "locomotion", "balance", "hybrid"]
    )

    static let manipulatorPickAndPlace = LearningProjectTemplate(
        templateID: "manipulator-pick-and-place-v1",
        displayName: "Manipulator Pick And Place",
        summary: "Generic manipulation template for reaching, grasping, lifting, and placing with bounded joint commands.",
        domain: .manipulator,
        task: "pickAndPlace",
        taskProfileID: nil,
        descriptor: LearningProjectDescriptorReference(
            descriptorID: "generated-manipulator",
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
            isBounded: true
        ),
        policy: .simpleFeedForward(
            observationDimension: 8,
            actionDimension: 7,
            actionEncoding: .jointTargets
        ),
        compute: localCompute(workerCount: 2, candidateEvaluationConcurrency: 2),
        tags: ["manipulator", "pick", "place", "grasp", "hybrid"]
    )

    static let automotiveLaneKeeping = LearningProjectTemplate(
        templateID: "automotive-lane-keeping-v1",
        displayName: "Automotive Lane Keeping",
        summary: "Generic vehicle template for lane keeping, speed tracking, and safety envelope validation.",
        domain: .automotive,
        task: "laneKeeping",
        taskProfileID: nil,
        descriptor: LearningProjectDescriptorReference(
            descriptorID: "generated-road-vehicle",
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
            isBounded: true
        ),
        policy: .simpleFeedForward(
            observationDimension: 8,
            actionDimension: 3,
            actionEncoding: .vehicleSteerThrottleBrake
        ),
        compute: localCompute(workerCount: 2, candidateEvaluationConcurrency: 2),
        tags: ["automotive", "lane-keeping", "safety", "hybrid"]
    )

    private static func knownTaskEvaluationProfile(task: String) -> TaskEvaluationProfile {
        do {
            return try TaskEvaluationProfile.profile(task: task)
        } catch {
            preconditionFailure("Missing built-in task evaluation profile for \(task): \(error)")
        }
    }

    private static func localCompute(
        workerCount: Int,
        candidateEvaluationConcurrency: Int
    ) -> LearningProjectComputeProfile {
        let concurrency = max(100, candidateEvaluationConcurrency)
        return LearningProjectComputeProfile(
            preset: .local,
            workerCount: 1,
            candidateEvaluationConcurrency: concurrency,
            requiresMetal: true,
            targetAccelerator: .metal,
            usesMachineOptimizedParallelism: true,
            minimumPopulationSize: concurrency,
            estimatedDiskBytes: nil
        )
    }

    private static func genericSafetyGate(failOnTruncation: Bool) -> LearningProjectEvaluationGate {
        LearningProjectEvaluationGate(
            minimumRewardAverage: nil,
            minimumTaskPassRate: 1,
            minimumHoldTimeRatio: nil,
            maximumAltitudeErrorRatio: nil,
            failOnTruncation: failOnTruncation,
            requiredSafetyGates: [
                .modelBundleValidated,
                .deterministicReplayValidated,
                .scenarioRegressionPassed,
                .stressRegressionPassed,
                .safetyEnvelopeValidated,
                .telemetryComplete,
                .artifactLineageComplete
            ]
        )
    }

    private static func convergenceGoal(
        maxGenerationBudget: Int,
        patienceGenerations: Int
    ) -> LearningProjectConvergenceGoal {
        LearningProjectConvergenceGoal(
            kind: .convergence,
            targetTaskPassRate: 1,
            targetHoldTimeRatio: 1,
            maximumSafetyViolationRate: 0,
            minimumFitnessImprovement: 0.001,
            minimumTaskPassRateImprovement: 0.001,
            minimumHoldTimeRatioImprovement: 0.001,
            patienceGenerations: patienceGenerations,
            maxGenerationBudget: maxGenerationBudget
        )
    }

    private static func validationGateGoal() -> LearningProjectConvergenceGoal {
        LearningProjectConvergenceGoal(
            kind: .validationGate,
            targetTaskPassRate: 1,
            targetHoldTimeRatio: 1,
            maximumSafetyViolationRate: 0,
            minimumFitnessImprovement: 0,
            minimumTaskPassRateImprovement: 0,
            minimumHoldTimeRatioImprovement: 0,
            patienceGenerations: 1,
            maxGenerationBudget: 1
        )
    }

    private static func aerialNavigationObservation() -> LearningProjectObservationContract {
        LearningProjectObservationContract(
            schemaID: "aerial-navigation-observation-v1",
            channelCount: 10,
            channels: [
                LearningProjectObservationChannel(index: 0, name: "gyroX", unit: "rad/s", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 1, name: "gyroY", unit: "rad/s", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 2, name: "gyroZ", unit: "rad/s", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 3, name: "accelX", unit: "m/s^2", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 4, name: "accelY", unit: "m/s^2", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 5, name: "accelZ", unit: "m/s^2", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 6, name: "altitudeZ", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 7, name: "verticalVelocityZ", unit: "m/s", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 8, name: "targetDeltaXY", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 9, name: "constraintPressure", unit: nil, isStateChannel: false, isStressable: true)
            ]
        )
    }
}
