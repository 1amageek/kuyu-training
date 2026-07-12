import Foundation
import Testing
import KuyuTraining

@Test(.timeLimit(.minutes(1)))
func learningProgressSnapshotPreservesIterationMetrics() throws {
    let records = [
        TrainingRunIterationRecord(
            iteration: 0,
            recordedAt: Date(timeIntervalSince1970: 0),
            evaluation: TrainingRunIterationRecord.EvaluationRecord(
                evaluationHorizon: 0,
                metrics: ["score": 0.31, "trainingLoss": 1.1]
            )
        ),
        TrainingRunIterationRecord(
            iteration: 1,
            recordedAt: Date(timeIntervalSince1970: 1),
            decision: TrainingRunIterationRecord.CandidateDecision(
                accepted: true,
                rejectionReasons: [],
                horizonHealth: [
                    "failureRate": 0.2,
                    "episodeCount": 5,
                    "failureCount": 1,
                ]
            ),
            evaluation: TrainingRunIterationRecord.EvaluationRecord(
                evaluationHorizon: 0,
                metrics: ["score": 0.62, "suitePassed": 1, "trainingLoss": 0.4]
            )
        ),
    ]

    let snapshot = LearningProgressSnapshot(records: records)

    #expect(snapshot.attempts.map(\.evaluationScore) == [0.31, 0.62])
    #expect(snapshot.attempts.map(\.trainingLoss) == [1.1, 0.4])
    #expect(snapshot.attempts[1].failureRate == 0.2)
    #expect(snapshot.latestEvaluationAttempt == 2)
    #expect(snapshot.latestEvaluationPassed == true)
    #expect(snapshot.hasGenerationLineage)
    #expect(snapshot.acceptedGenerationCount == 1)
}

@Test(.timeLimit(.minutes(1)))
func learningProgressSnapshotKeepsFailureObservationsDistinct() {
    let records = [
        TrainingRunIterationRecord(
            iteration: 0,
            recordedAt: Date(timeIntervalSince1970: 0),
            failureEpisodes: [
                TrainingRunIterationRecord.FailureEpisode(
                    scenario: "attitude",
                    seed: 7,
                    terminalStep: 42,
                    reason: "sustained-fall"
                ),
                TrainingRunIterationRecord.FailureEpisode(
                    scenario: "attitude",
                    seed: 7,
                    terminalStep: 43,
                    reason: "sustained-fall"
                ),
            ]
        ),
    ]

    let snapshot = LearningProgressSnapshot(records: records)

    #expect(snapshot.failureObservations.count == 2)
    #expect(snapshot.failureGroups.count == 1)
    #expect(snapshot.failureGroups[0].observationCount == 2)
    #expect(snapshot.failureGroups[0].latestTerminalStep == 43)
}
