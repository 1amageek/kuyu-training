import Foundation
import Testing

@testable import KuyuTraining

@Suite("Training reinforcement stopping settings")
struct TrainingReinforcementStoppingSettingsTests {
  @Test func rejectsInvalidDecodedSettings() {
    let data = Data(
      """
      {
        "minimumIterationCount": 0,
        "plateauWindow": 10,
        "unsafeWindow": 2
      }
      """.utf8
    )

    #expect(throws: TrainingReinforcementStoppingSettings.ValidationError.self) {
      _ = try JSONDecoder().decode(
        TrainingReinforcementStoppingSettings.self,
        from: data
      )
    }
  }

  @Test func convergencePoliciesKeepUnsafeStoppingStrict() {
    #expect(TrainingReinforcementStoppingSettings.convergence.minimumIterationCount == 10)
    #expect(TrainingReinforcementStoppingSettings.convergence.plateauWindow == 10)
    #expect(TrainingReinforcementStoppingSettings.convergence.unsafeWindow == 2)
    #expect(TrainingReinforcementStoppingSettings.extendedConvergence.unsafeWindow == 2)
  }
}
