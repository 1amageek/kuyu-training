import Testing
@testable import KuyuTraining

@Test func trainingDatasetRecordCanBeCreated() {
    let record = TrainingDatasetRecord(
        time: 0.0,
        sensors: [TrainingSensorSample(channelIndex: 0, value: 0.5, timestamp: 0.0)],
        driveIntents: [TrainingDriveIntent(driveIndex: 0, value: 0.2)],
        reflexCorrections: []
    )
    #expect(record.time == 0.0)
    #expect(record.sensors.count == 1)
    #expect(record.driveIntents.count == 1)
}

@Test func onlineDataBufferRejectsZeroCapacity() {
    #expect(throws: OnlineDataBuffer.ValidationError.nonPositiveMaxRecords) {
        try OnlineDataBuffer(maxRecords: 0)
    }
}

@Test func curriculumConfigRejectsInvalidValues() {
    #expect(throws: CurriculumController.Config.ValidationError.nonPositive("totalLevels")) {
        try CurriculumController.Config(totalLevels: 0)
    }
    #expect(throws: CurriculumController.Config.ValidationError.outOfRange("advanceThreshold")) {
        try CurriculumController.Config(advanceThreshold: 0.0)
    }
    #expect(throws: CurriculumController.Config.ValidationError.outOfRange("advanceThreshold")) {
        try CurriculumController.Config(advanceThreshold: 1.1)
    }
}
