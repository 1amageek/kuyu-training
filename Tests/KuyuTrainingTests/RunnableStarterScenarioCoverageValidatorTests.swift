import Testing
import KuyuTraining

@Test func runnableStarterScenarioCoverageValidatorAcceptsDefaultCatalog() throws {
    let catalog = LearningProjectTemplateCatalog()
    let starterIDs = catalog.templates.filter(\.isRunnableStarter).map(\.templateID)

    #expect(starterIDs == [
        "aerial-drone-autonomy-starter-v1",
        "aerial-single-prop-lift-recovery-v1",
    ])
    try RunnableStarterScenarioCoverageValidator().validate(catalog: catalog)
}

@Test func runnableStarterScenarioCoverageValidatorRejectsCatalogWithoutStarters() {
    let catalog = LearningProjectTemplateCatalog(templates: [.droneHoverStabilization])

    #expect(throws: RunnableStarterScenarioCoverageValidator.ValidationError.noRunnableStarterTemplates) {
        try RunnableStarterScenarioCoverageValidator().validate(catalog: catalog)
    }
}

@Test func runnableStarterScenarioCoverageValidatorRejectsUnresolvedSuite() throws {
    let base = LearningProjectTemplate.singlePropLiftRecovery
    let stage = try #require(base.primaryRunnableTrainingStage)
    let brokenStage = copy(stage, suiteIDs: [99])
    let template = copy(base, replacing: stage.stageID, with: brokenStage)

    #expect(throws: RunnableStarterScenarioCoverageValidator.ValidationError.unresolvedSuite(
        templateID: base.templateID,
        stageID: stage.stageID,
        suiteID: 99
    )) {
        try RunnableStarterScenarioCoverageValidator().validate(template)
    }
}

@Test func runnableStarterScenarioCoverageValidatorRejectsInvalidEpisodeCount() throws {
    let base = LearningProjectTemplate.droneAutonomyStarter
    let stage = try #require(base.primaryRunnableTrainingStage)
    let brokenStage = copy(stage, seedCount: 0)
    let template = copy(base, replacing: stage.stageID, with: brokenStage)

    #expect(throws: RunnableStarterScenarioCoverageValidator.ValidationError.invalidEpisodeCount(
        templateID: base.templateID,
        stageID: stage.stageID,
        count: 0
    )) {
        try RunnableStarterScenarioCoverageValidator().validate(template)
    }
}

private func copy(
    _ stage: LearningProjectTrainingStage,
    suiteIDs: [Int]? = nil,
    seedCount: Int? = nil
) -> LearningProjectTrainingStage {
    LearningProjectTrainingStage(
        stageID: stage.stageID,
        kind: stage.kind,
        displayName: stage.displayName,
        task: stage.task,
        taskProfileID: stage.taskProfileID,
        suiteIDs: suiteIDs ?? stage.suiteIDs,
        seedCount: seedCount ?? stage.seedCount,
        episodesPerSuite: stage.episodesPerSuite,
        generationLimit: stage.generationLimit,
        convergenceGoal: stage.convergenceGoal,
        executionMode: stage.executionMode,
        dependsOnStageIDs: stage.dependsOnStageIDs,
        capabilities: stage.capabilities
    )
}

private func copy(
    _ template: LearningProjectTemplate,
    replacing stageID: String,
    with replacement: LearningProjectTrainingStage
) -> LearningProjectTemplate {
    let stages = template.curriculum.trainingStages.map { stage in
        stage.stageID == stageID ? replacement : stage
    }
    let curriculum = LearningProjectCurriculum(
        suiteIDs: template.curriculum.suiteIDs,
        seedCount: template.curriculum.seedCount,
        episodesPerSuite: template.curriculum.episodesPerSuite,
        populationSize: template.curriculum.populationSize,
        generationLimit: template.curriculum.generationLimit,
        convergenceGoal: template.curriculum.convergenceGoal,
        eliteCount: template.curriculum.eliteCount,
        maxStepCount: template.curriculum.maxStepCount,
        trainingStages: stages
    )
    return LearningProjectTemplate(
        schemaVersion: template.schemaVersion,
        templateID: template.templateID,
        displayName: template.displayName,
        summary: template.summary,
        domain: template.domain,
        task: template.task,
        taskProfileID: template.taskProfileID,
        robotManifest: template.robotManifest,
        modelBundlePolicy: template.modelBundlePolicy,
        trainingStrategy: template.trainingStrategy,
        curriculum: curriculum,
        evaluationGate: template.evaluationGate,
        observation: template.observation,
        action: template.action,
        policy: template.policy,
        compute: template.compute,
        tags: template.tags
    )
}
