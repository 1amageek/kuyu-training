import Foundation
import Testing
@testable import KuyuTraining

@Test(.timeLimit(.minutes(1)))
func trainingWorkProgressPreservesTypedScenarioScope() throws {
    let timestamp = Date(timeIntervalSince1970: 42)
    let progress = try TrainingWorkProgress(
        scope: TrainingWorkScope(runID: "run", generationIndex: 3),
        phase: .rollout,
        state: .advanced,
        unit: TrainingWorkUnit(
            kind: .scenario,
            identifier: "6/KUY-ATT-1/1001",
            suiteIndex: 6,
            scenarioID: "KUY-ATT-1",
            scenarioSeed: 1001
        ),
        completedUnitCount: 2,
        totalUnitCount: 6,
        populationSize: 4,
        timestamp: timestamp
    )

    #expect(progress.scope.generationIndex == 3)
    #expect(progress.unit.suiteIndex == 6)
    #expect(progress.unit.scenarioID == "KUY-ATT-1")
    #expect(progress.unit.scenarioSeed == 1001)
    #expect(progress.fractionCompleted == 1.0 / 3.0)
}

@Test(.timeLimit(.minutes(1)))
func trainingWorkProgressRejectsInvalidCounts() throws {
    let scope = try TrainingWorkScope(runID: "run")
    let unit = try TrainingWorkUnit(kind: .batch, identifier: "batch-0")

    #expect(throws: TrainingWorkContractError.invalidUnitCount(completed: 2, total: 1)) {
        _ = try TrainingWorkProgress(
            scope: scope,
            phase: .optimization,
            state: .advanced,
            unit: unit,
            completedUnitCount: 2,
            totalUnitCount: 1
        )
    }
}

@Test(.timeLimit(.minutes(1)))
func trainingWorkProgressRejectsInvalidDecodedCounts() throws {
    let json = Data("""
    {
      "scope": {"runID": "run"},
      "phase": "rollout",
      "state": "advanced",
      "unit": {"kind": "controlStep", "identifier": "step"},
      "completedUnitCount": 2,
      "totalUnitCount": 1,
      "timestamp": 0
    }
    """.utf8)

    #expect(throws: TrainingWorkContractError.invalidUnitCount(completed: 2, total: 1)) {
        _ = try JSONDecoder().decode(TrainingWorkProgress.self, from: json)
    }
}

@Test(.timeLimit(.minutes(1)))
func trainingWorkProgressRejectsInvalidDecodedScopeAndUnit() throws {
    let invalidScope = Data("""
    {"runID": " ", "generationIndex": -1}
    """.utf8)
    let invalidUnit = Data("""
    {"kind": "scenario", "identifier": " ", "suiteIndex": -1}
    """.utf8)

    #expect(throws: TrainingWorkContractError.emptyIdentifier("runID")) {
        _ = try JSONDecoder().decode(TrainingWorkScope.self, from: invalidScope)
    }
    #expect(throws: TrainingWorkContractError.emptyIdentifier("workUnit.identifier")) {
        _ = try JSONDecoder().decode(TrainingWorkUnit.self, from: invalidUnit)
    }
}
