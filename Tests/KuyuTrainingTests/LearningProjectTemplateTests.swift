import Foundation
import KuyuTraining
import Testing

@Test func learningProjectTemplateCatalogProvidesValidDroneTemplates() throws {
    let validator = LearningProjectTemplateValidator(requiresKnownTaskProfile: true)

    try validator.validate(.droneLiftStarter)
    try validator.validate(.singlePropLiftRecovery)

    let catalog = LearningProjectTemplateCatalog()
    #expect(catalog.template(id: "aerial-drone-lift-starter-v1")?.domain == .aerialDrone)
    #expect(catalog.template(id: "aerial-single-prop-lift-recovery-v1")?.action.driveCount == 1)
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
    let template = LearningProjectTemplate.droneLiftStarter
    let data = try JSONEncoder().encode(template)
    let decoded = try JSONDecoder().decode(LearningProjectTemplate.self, from: data)

    #expect(decoded == template)
    #expect(decoded.observation.channelCount == 8)
    #expect(decoded.trainingStrategy.evolutionSearchStrategy == .qualityDiversity)
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
    let base = LearningProjectTemplate.droneLiftStarter
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
        compute: base.compute,
        tags: base.tags
    )

    do {
        try LearningProjectTemplateValidator().validate(template)
        Issue.record("Expected profile mismatch to throw.")
    } catch LearningProjectTemplateValidationError.invalidTaskProfile(let expected, let actual) {
        #expect(expected == "lift-v1")
        #expect(actual == "wrong-profile")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func learningProjectTemplateRejectsIncompleteObservationContract() throws {
    let base = LearningProjectTemplate.droneLiftStarter
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
        compute: base.compute,
        tags: base.tags
    )

    do {
        try LearningProjectTemplateValidator().validate(template)
        Issue.record("Expected incomplete observation contract to throw.")
    } catch LearningProjectTemplateValidationError.observationChannelCountMismatch(let expected, let actual) {
        #expect(expected == 8)
        #expect(actual == 7)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func learningProjectTemplateRejectsNonFiniteEvaluationGate() throws {
    let base = LearningProjectTemplate.droneLiftStarter
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
