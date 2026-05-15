import Foundation
import KuyuTraining
import Testing

@Test func learningProjectTemplateCatalogProvidesValidDroneTemplates() throws {
    let validator = LearningProjectTemplateValidator(requiresKnownTaskProfile: true)

    try validator.validate(.singlePropLiftRecovery)

    let catalog = LearningProjectTemplateCatalog()
    #expect(catalog.template(id: "aerial-drone-autonomy-starter-v1")?.domain == .aerialDrone)
    #expect(catalog.template(id: "aerial-single-prop-lift-recovery-v1")?.action.driveCount == 1)
}

@Test func learningProjectTemplateCatalogClassifiesExecutionLevels() {
    let catalog = LearningProjectTemplateCatalog()
    let levelsByID = Dictionary(uniqueKeysWithValues: catalog.templates.map { ($0.templateID, $0.executionLevel) })

    #expect(levelsByID["aerial-drone-autonomy-starter-v1"] == .runnableStarter)
    #expect(levelsByID["aerial-single-prop-lift-recovery-v1"] == .runnableStarter)
    #expect(levelsByID["aerial-drone-waypoint-navigation-v1"] == .requiresExistingModel)
    #expect(levelsByID["ground-robot-point-navigation-v1"] == .designOnly)
    #expect(levelsByID["aerial-drone-hover-stabilization-v1"] == .designOnly)
    #expect(levelsByID["legged-robot-locomotion-v1"] == .designOnly)
    #expect(levelsByID["manipulator-pick-and-place-v1"] == .designOnly)
    #expect(levelsByID["automotive-lane-keeping-v1"] == .designOnly)
}

@Test func learningProjectTemplateCatalogProvidesUniquePresetIDs() {
    let catalog = LearningProjectTemplateCatalog()
    let ids = catalog.templates.map(\.templateID)

    #expect(ids.count == Set(ids).count)
    #expect(ids.count >= 8)
}

@Test func learningProjectTemplateCatalogPresetsValidateInAuthoringMode() throws {
    let validator = LearningProjectTemplateValidator(requiresKnownTaskProfile: false)

    for template in LearningProjectTemplateCatalog().templates {
        try validator.validate(template)
    }
}

@Test func learningProjectTemplateCatalogCoversAutonomousDomains() {
    let domains = Set(LearningProjectTemplateCatalog().templates.map(\.domain))

    #expect(domains.contains(.aerialDrone))
    #expect(domains.contains(.groundRobot))
    #expect(domains.contains(.manipulator))
    #expect(domains.contains(.automotive))
}

@Test func learningProjectTemplateRoundTripsThroughJSON() throws {
    let template = LearningProjectTemplate.droneAutonomyStarter
    let data = try JSONEncoder().encode(template)
    let decoded = try JSONDecoder().decode(LearningProjectTemplate.self, from: data)

    #expect(decoded == template)
    #expect(decoded.observation.channelCount == 64)
    #expect(decoded.trainingStrategy.evolutionSearchStrategy == .qualityDiversity)
}

@Test func droneStarterTemplateDefinesMultiStageAutonomyCurriculum() throws {
    let template = LearningProjectTemplate.droneAutonomyStarter
    let stages = template.curriculum.trainingStages
    let resolver = LearningProjectCurriculumStageResolver()

    try LearningProjectTemplateValidator(requiresKnownTaskProfile: true).validate(template)

    #expect(template.displayName == "Drone Autonomy Starter")
    #expect(template.task == "aerialAutonomy")
    #expect(template.taskProfileID == nil)
    #expect(template.isRunnableStarter)
    #expect(template.curriculum.suiteIDs == [6])
    #expect(template.curriculum.seedCount == 2)
    #expect(template.curriculum.populationSize >= 24)
    #expect(template.curriculum.convergenceGoal.kind == .convergence)
    #expect(template.curriculum.generationLimit >= 1_000)
    #expect(template.curriculum.convergenceGoal.patienceGenerations >= 50)
    #expect(template.primaryRunnableTrainingStage?.stageID == "lift-foundation")
    #expect(template.primaryRunnableTrainingStage?.kind == .reinforcement)
    #expect(template.primaryRunnableTrainingStage?.suiteIDs == [6])
    #expect(template.primaryRunnableTrainingStage?.seedCount == 2)
    #expect(template.primaryRunnableTrainingStage?.convergenceGoal.kind == .convergence)
    #expect(try resolver.runnableStages(in: template.curriculum).map(\.stageID) == ["lift-foundation"])
    #expect(try resolver.nextRunnableStage(in: template.curriculum, completedStageIDs: [])?.stageID == "lift-foundation")
    #expect(try resolver.nextRunnableStage(
        in: template.curriculum,
        completedStageIDs: ["lift-foundation"]
    ) == nil)
    #expect(stages.count >= 5)
    #expect(stages.contains { $0.stageID == "hover-stabilization" })
    #expect(stages.contains { $0.stageID == "trajectory-tracking" && $0.kind == .evolution && $0.executionMode == .parallel })
    #expect(stages.contains { $0.stageID == "disturbance-recovery" && $0.kind == .stress && $0.executionMode == .parallel })
    #expect(stages.contains { $0.stageID == "full-regression" && $0.kind == .regression && $0.convergenceGoal.kind == .validationGate })
}

@Test func runnableStarterTemplateStrictValidationAllowsMetaTaskWhenPrimaryStageIsKnown() throws {
    let template = LearningProjectTemplate.droneAutonomyStarter

    #expect(template.task == "aerialAutonomy")
    #expect(template.primaryRunnableTrainingStage?.task == "lift")
    try LearningProjectTemplateValidator(requiresKnownTaskProfile: true).validate(template)
}

@Test func singlePropTemplateDefinesExecutableRecoveryStage() throws {
    let template = LearningProjectTemplate.singlePropLiftRecovery

    try LearningProjectTemplateValidator(requiresKnownTaskProfile: false).validate(template)

    #expect(template.executionLevel == .runnableStarter)
    #expect(template.isRunnableStarter)
    #expect(template.primaryRunnableTrainingStage?.stageID == "single-prop-lift-recovery")
    #expect(template.primaryRunnableTrainingStage?.kind == .evolution)
    #expect(template.primaryRunnableTrainingStage?.task == "singleLift")
    #expect(template.primaryRunnableTrainingStage?.taskProfileID != nil)
    #expect(template.primaryRunnableTrainingStage?.convergenceGoal.kind == .convergence)
    #expect(template.primaryRunnableTrainingStage?.generationLimit ?? 0 >= 1_000)
    #expect(template.curriculum.trainingStages.contains { $0.stageID == "single-prop-regression" && $0.kind == .regression })
}

@Test func learningProjectTemplatesUseConvergenceAsDefaultCompletionGoal() throws {
    let catalog = LearningProjectTemplateCatalog()

    for template in catalog.templates {
        try LearningProjectTemplateValidator(requiresKnownTaskProfile: false).validate(template)
        #expect(template.curriculum.convergenceGoal.kind == .convergence)
        #expect(template.curriculum.generationLimit == template.curriculum.convergenceGoal.maxGenerationBudget)
        for stage in template.curriculum.trainingStages where stage.convergenceGoal.kind == .convergence {
            #expect(stage.generationLimit == stage.convergenceGoal.maxGenerationBudget)
            #expect(stage.generationLimit >= stage.convergenceGoal.patienceGenerations)
        }
    }
}

@Test func learningProjectTemplatesRequireMetalAndMachineOptimizedParallelism() throws {
    for template in LearningProjectTemplateCatalog().templates {
        #expect(template.compute.requiresMetal)
        #expect(template.compute.targetAccelerator == .metal)
        #expect(template.compute.usesMachineOptimizedParallelism)
        #expect(template.curriculum.populationSize >= template.compute.minimumPopulationSize)
        #expect(template.compute.candidateEvaluationConcurrency <= template.compute.minimumPopulationSize)
    }
}

@Test func learningProjectTemplateRejectsPopulationBelowComputeMinimum() throws {
    let base = LearningProjectTemplate.droneAutonomyStarter
    let template = LearningProjectTemplate(
        templateID: base.templateID,
        displayName: base.displayName,
        summary: base.summary,
        domain: base.domain,
        task: base.task,
        taskProfileID: base.taskProfileID,
        descriptor: base.descriptor,
        modelBundlePolicy: base.modelBundlePolicy,
        trainingStrategy: base.trainingStrategy,
        curriculum: base.curriculum,
        evaluationGate: base.evaluationGate,
        observation: base.observation,
        action: base.action,
        policy: base.policy,
        compute: LearningProjectComputeProfile(
            preset: base.compute.preset,
            workerCount: base.compute.workerCount,
            candidateEvaluationConcurrency: base.compute.candidateEvaluationConcurrency,
            requiresMetal: base.compute.requiresMetal,
            targetAccelerator: base.compute.targetAccelerator,
            usesMachineOptimizedParallelism: base.compute.usesMachineOptimizedParallelism,
            minimumPopulationSize: base.curriculum.populationSize + 1,
            estimatedDiskBytes: base.compute.estimatedDiskBytes
        ),
        tags: base.tags
    )

    do {
        try LearningProjectTemplateValidator(requiresKnownTaskProfile: true).validate(template)
        Issue.record("Expected population below compute minimum to throw.")
    } catch LearningProjectTemplateValidationError.invalidComputeProfile(let reason) {
        #expect(reason == "population-below-compute-minimum")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func learningProjectTemplateAllowsGenericRobotTasksWhenProfileIsNotRequired() throws {
    let template = LearningProjectTemplate.groundRobotPointNavigation
    let validator = LearningProjectTemplateValidator(requiresKnownTaskProfile: false)

    try validator.validate(template)

    #expect(template.domain == .groundRobot)
    #expect(template.taskProfileID == nil)
    #expect(template.descriptor.robotClass == .groundVehicle)
}

@Test func learningProjectTemplateRejectsUnknownTaskWhenKnownProfileIsRequired() throws {
    let template = LearningProjectTemplate.groundRobotPointNavigation
    let validator = LearningProjectTemplateValidator(requiresKnownTaskProfile: true)

    do {
        try validator.validate(template)
        Issue.record("Expected strict task profile validation to reject unknown task.")
    } catch LearningProjectTemplateValidationError.unsupportedTaskProfile(let task) {
        #expect(task == "pointNavigation")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func learningProjectTemplateRejectsMismatchedKnownTaskProfile() throws {
    let base = LearningProjectTemplate.singlePropLiftRecovery
    let template = LearningProjectTemplate(
        templateID: base.templateID,
        displayName: base.displayName,
        summary: base.summary,
        domain: base.domain,
        task: base.task,
        taskProfileID: "wrong-profile",
        descriptor: base.descriptor,
        modelBundlePolicy: base.modelBundlePolicy,
        trainingStrategy: base.trainingStrategy,
        curriculum: base.curriculum,
        evaluationGate: base.evaluationGate,
        observation: base.observation,
        action: base.action,
        policy: base.policy,
        compute: base.compute,
        tags: base.tags
    )

    do {
        try LearningProjectTemplateValidator().validate(template)
        Issue.record("Expected profile mismatch to throw.")
    } catch LearningProjectTemplateValidationError.invalidTaskProfile(let expected, let actual) {
        #expect(expected == "singleLift-v1")
        #expect(actual == "wrong-profile")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func learningProjectTemplateRejectsIncompleteObservationContract() throws {
    let base = LearningProjectTemplate.droneAutonomyStarter
    let template = LearningProjectTemplate(
        templateID: base.templateID,
        displayName: base.displayName,
        summary: base.summary,
        domain: base.domain,
        task: base.task,
        taskProfileID: base.taskProfileID,
        descriptor: base.descriptor,
        modelBundlePolicy: base.modelBundlePolicy,
        trainingStrategy: base.trainingStrategy,
        curriculum: base.curriculum,
        evaluationGate: base.evaluationGate,
        observation: LearningProjectObservationContract(
            schemaID: base.observation.schemaID,
            channelCount: base.observation.channelCount,
            channels: Array(base.observation.channels.dropLast())
        ),
        action: base.action,
        policy: base.policy,
        compute: base.compute,
        tags: base.tags
    )

    do {
        try LearningProjectTemplateValidator().validate(template)
        Issue.record("Expected incomplete observation contract to throw.")
    } catch LearningProjectTemplateValidationError.observationChannelCountMismatch(let expected, let actual) {
        #expect(expected == 64)
        #expect(actual == 63)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func learningProjectTemplateRejectsNonFiniteEvaluationGate() throws {
    let base = LearningProjectTemplate.droneAutonomyStarter
    let template = LearningProjectTemplate(
        templateID: base.templateID,
        displayName: base.displayName,
        summary: base.summary,
        domain: base.domain,
        task: base.task,
        taskProfileID: base.taskProfileID,
        descriptor: base.descriptor,
        modelBundlePolicy: base.modelBundlePolicy,
        trainingStrategy: base.trainingStrategy,
        curriculum: base.curriculum,
        evaluationGate: LearningProjectEvaluationGate(
            minimumRewardAverage: .infinity,
            minimumTaskPassRate: 1,
            minimumHoldTimeRatio: 1,
            maximumAltitudeErrorRatio: 1,
            failOnTruncation: false,
            requiredSafetyGates: []
        ),
        observation: base.observation,
        action: base.action,
        policy: base.policy,
        compute: base.compute,
        tags: base.tags
    )

    do {
        try LearningProjectTemplateValidator().validate(template)
        Issue.record("Expected non-finite reward gate to throw.")
    } catch LearningProjectTemplateValidationError.invalidEvaluationGate(let reason) {
        #expect(reason == "non-finite-minimum-reward")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
