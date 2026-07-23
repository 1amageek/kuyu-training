import KuyuTraining
import Testing

@Test func replacingCostPreservesEveryOtherTrainingRecordField() {
    let source = TrainingDatasetRecord(
        time: 0.01,
        policyDecisionID: "episode#decision=2",
        actionObservationTime: 0.005,
        actionObservationState: [1, 2, 3],
        sensors: [TrainingSensorSample(channelIndex: 0, value: 0.25, timestamp: 0.005)],
        driveIntents: [TrainingDriveIntent(driveIndex: 0, value: 0.4, parameters: [])],
        reflexCorrections: [
            TrainingReflexCorrection(driveIndex: 0, clamp: 0.8, damping: 0.1, delta: -0.05),
        ],
        physicsState: [4, 5, 6],
        actualState: [7, 8, 9],
        actionValues: [0.4],
        actuatorCommandValues: [0.35],
        continueValue: 0,
        reward: 1.5,
        cost: 0.1,
        done: false,
        truncated: true,
        episodeId: "episode",
        policyId: "policy"
    )

    let updated = source.replacingCost(with: 0.75)

    #expect(updated.cost == 0.75)
    #expect(updated.replacingCost(with: source.cost) == source)
}
