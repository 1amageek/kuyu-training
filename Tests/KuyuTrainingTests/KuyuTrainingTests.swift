import Testing
@testable import KuyuTraining

@Test func trainingDatasetTypesExist() {
    // Verify training types are accessible
    let record = TrainingRecord(
        scenarioId: "test",
        stepIndex: 0,
        sensorValues: [],
        actuatorValues: [],
        driveIntents: []
    )
    #expect(record.scenarioId == "test")
}
