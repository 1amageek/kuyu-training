import Foundation
import KuyuTraining
import Testing

@Test(.timeLimit(.minutes(1)))
func learningUpdateExecutorPreservesTypedRequestAndResult() async throws {
  let request = LearningUpdateRequest(
    runID: "run-1",
    datasetURL: URL(fileURLWithPath: "/tmp/dataset", isDirectory: true),
    sourceBundle: ModelBundleReference(
      bundleID: "source-1",
      kind: .source,
      url: URL(fileURLWithPath: "/tmp/source", isDirectory: true),
      contentHash: String(repeating: "a", count: 64)
    ),
    candidateBundleID: "candidate-1",
    candidateBundleURL: URL(
      fileURLWithPath: "/tmp/candidate",
      isDirectory: true
    ),
    plan: LearningUpdatePlan(epochCount: 2, minibatchSize: 8)
  )
  let expected = LearningUpdateResult(
    runID: request.runID,
    source: LearningUpdateSourceIdentity(
      datasetID: "dataset-1",
      recordsDigest: String(repeating: "b", count: 64),
      policyID: "policy-1",
      checkpointDigest: String(repeating: "c", count: 64),
      actorInputContractDigest: String(repeating: "d", count: 64),
      criticInputContractDigest: String(repeating: "e", count: 64)
    ),
    transitionCount: 32,
    metrics: LearningUpdateMetrics(
      updateCount: 1,
      policyLoss: -0.1,
      rewardValueLoss: 0.2,
      costValueLoss: 0.3,
      entropy: 0.4,
      approximateKL: 0.01,
      clipFraction: 0.02,
      rewardAdvantageMean: 0.5,
      costAdvantageMean: 0.1,
      gradientNorm: 0.9,
      lagrangeMultiplier: 0.2
    ),
    candidate: ModelBundleReference(
      bundleID: request.candidateBundleID,
      kind: .candidate,
      url: request.candidateBundleURL,
      contentHash: String(repeating: "f", count: 64)
    )
  )
  let executor = AnyLearningUpdateExecutor { received in
    #expect(received == request)
    return expected
  }

  #expect(try await executor.execute(request) == expected)
}
