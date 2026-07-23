import Foundation
import Testing

@testable import KuyuTraining

@Suite("Training candidate refinement policy")
struct TrainingCandidateRefinementPolicyTests {
    @Test func candidateCountPreservesEliteCapacity() {
        let policy = TrainingCandidateRefinementPolicy(
            candidateFraction: 0.05,
            minimumCandidateCount: 1
        )

        #expect(policy.candidateCount(populationSize: 100, eliteCount: 10) == 10)
    }

    @Test func invalidFractionDoesNotTrapBeforeValidation() {
        let policy = TrainingCandidateRefinementPolicy(candidateFraction: .nan)

        #expect(policy.candidateCount(populationSize: 4, eliteCount: 2) == 2)
        #expect(throws: TrainingCandidateRefinementPolicy.ValidationError.self) {
            try policy.validate()
        }
    }

    @Test func decoderAcceptsBoundedRefinementFidelity() throws {
        let data = Data(
            """
            {
              "evaluationFidelity": {
                "kind": "screening",
                "maximumControlStepsPerEpisode": 1000
              },
              "candidateFraction": 0.25,
              "minimumCandidateCount": 1,
              "retainsIncumbent": true
            }
            """.utf8
        )

        let policy = try JSONDecoder().decode(
            TrainingCandidateRefinementPolicy.self,
            from: data
        )

        #expect(
            policy.evaluationFidelity
                == .screening(maximumControlStepsPerEpisode: 1_000)
        )
    }
}
