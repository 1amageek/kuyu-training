import Foundation
import Testing

@testable import KuyuTraining

@Suite("Training evaluation fidelity")
struct TrainingEvaluationFidelityTests {
    @Test func codecPreservesStableScreeningShape() throws {
        let fidelity = TrainingEvaluationFidelity.screening(
            maximumControlStepsPerEpisode: 1_000
        )

        let data = try JSONEncoder().encode(fidelity)
        let decoded = try JSONDecoder().decode(
            TrainingEvaluationFidelity.self,
            from: data
        )

        #expect(decoded == fidelity)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["kind"] as? String == "screening")
        #expect(object["maximumControlStepsPerEpisode"] as? Int == 1_000)
    }

    @Test func decoderRejectsNonPositiveScreeningBudget() {
        let data = Data(
            """
            {"kind":"screening","maximumControlStepsPerEpisode":0}
            """.utf8
        )

        #expect(
            throws: TrainingEvaluationFidelity.ValidationError
                .invalidMaximumControlSteps(0)
        ) {
            _ = try JSONDecoder().decode(
                TrainingEvaluationFidelity.self,
                from: data
            )
        }
    }

    @Test func decoderRejectsStepBudgetForFullScenario() {
        let data = Data(
            """
            {"kind":"fullScenario","maximumControlStepsPerEpisode":100}
            """.utf8
        )

        #expect(
            throws: TrainingEvaluationFidelity.ValidationError
                .unexpectedMaximumControlSteps(100)
        ) {
            _ = try JSONDecoder().decode(
                TrainingEvaluationFidelity.self,
                from: data
            )
        }
    }
}
