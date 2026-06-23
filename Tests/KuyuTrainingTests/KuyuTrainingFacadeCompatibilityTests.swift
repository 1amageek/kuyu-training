import Foundation
import Testing
import KuyuTraining

@Test func kuyuTrainingFacadeReexportsSplitTargetPublicTypes() throws {
    let runID: TrainingRunID = "facade-run"
    let evaluation = CandidateEvaluation(
        candidate: "candidate-a",
        candidateID: "candidate-a",
        fitness: 1.0
    )
    var health = RolloutHealth()
    health.addEpisodeSummary(
        done: true,
        truncated: false,
        failureReason: nil,
        terminalReason: nil,
        rewardSum: 1.0,
        maxOmega: 0.1,
        maxTilt: 0.2,
        minAltitude: 1.0
    )
    let dataset = TrainingDatasetRecord(
        time: 0,
        sensors: [],
        driveIntents: [],
        reflexCorrections: []
    )
    let decoder = TrainingRunContractCodec.makeDecoder()
    let decodedDate = try decoder.decode(Date.self, from: Data("\"1970-01-01T00:00:00Z\"".utf8))

    #expect(runID.rawValue == "facade-run")
    #expect(evaluation.candidateID == "candidate-a")
    #expect(health.episodeCount == 1)
    #expect(dataset.time == 0)
    #expect(decodedDate.timeIntervalSince1970 == 0)
    #expect(TrainingRunContractSchema.manifestFileName == "manifest.json")
}
